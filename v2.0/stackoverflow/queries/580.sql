-- {"query": "580.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3192}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        extract(year from u.creationdate) as signup_year,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
posts_aug as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.parentid,
        p.acceptedanswerid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.tags,
        p.title,
        coalesce(p.contentlicense, 'unknown') as contentlicense_norm,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        case when p.posttypeid = 1 then 1 when p.posttypeid = 2 then 0 else null end as is_question
    from posts p
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
accepted_latency as (
    select
        q.id as question_id,
        q.creationdate as q_created,
        a.creationdate as acc_created,
        extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
),
user_post_agg as (
    select
        pu.owneruserid as user_id,
        count(*) filter (where pu.posttypeid = 1) as questions,
        count(*) filter (where pu.posttypeid = 2) as answers,
        sum(pu.score) as total_score,
        avg(nullif(pu.score,0)) as avg_nonzero_score,
        sum(pu.viewcount) as total_views,
        max(pu.creationdate) as last_post_at,
        count(*) filter (where pu.closeddate is not null) as closed_posts,
        count(distinct pu.parentid) filter (where pu.posttypeid = 2 and pu.parentid is not null) as distinct_questions_answered
    from posts_aug pu
    group by pu.owneruserid
),
commenter_activity as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by c.userid
),
tag_explode as (
    select
        p.id as post_id,
        lower(trim(tg.t)) as tag
    from posts_aug p
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(p.tags,'<>'), 2, greatest(length(coalesce(p.tags,'<>'))-2,0)), '><')) as t
    ) as tg
    where p.posttypeid = 1
),
user_top_tags as (
    select
        p.owneruserid as user_id,
        te.tag,
        count(*) as tag_q_count,
        row_number() over (partition by p.owneruserid order by count(*) desc, min(p.id)) as rn_tag
    from posts_aug p
    join tag_explode te on te.post_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, te.tag
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by v.postid
),
postlinks_dup as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links,
        max(pl.creationdate) as last_link_at
    from postlinks pl
    group by pl.postid
),
posthistory_closure as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopen_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        count(*) filter (where ph.posthistorytypeid in (35,36)) as migration_events
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by ph.postid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges,
        min(b.date) as first_badge_at,
        max(b.date) as last_badge_at
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by b.userid
),
question_metrics as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.score,
        p.viewcount,
        p.answercount,
        p.creationdate,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as favorites,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(phc.first_closed_at, p.closeddate) as first_closed_at,
        phc.close_events,
        phc.reopen_events,
        phc.migration_events,
        coalesce(pl.duplicate_links,0) as duplicate_links,
        coalesce(pl.related_links,0) as related_links,
        pl.last_link_at,
        al.hours_to_accept
    from posts_aug p
    left join votes_agg va on va.postid = p.id
    left join postlinks_dup pl on pl.postid = p.id
    left join posthistory_closure phc on phc.postid = p.id
    left join accepted_latency al on al.question_id = p.id
    where p.posttypeid = 1
),
location_rank as (
    select
        ru.location_norm,
        count(*) as users_in_location,
        percentile_cont(0.5) within group (order by ru.reputation) as median_rep,
        avg(ru.reputation) as avg_rep,
        max(ru.reputation) as max_rep
    from recent_users ru
    group by ru.location_norm
),
qualified_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.location_norm,
        ru.signup_year,
        ru.reputation,
        upa.questions,
        upa.answers,
        upa.total_score,
        upa.avg_nonzero_score,
        upa.total_views,
        upa.closed_posts,
        upa.distinct_questions_answered,
        ca.comments_count,
        ca.avg_comment_score,
        ub.badges_total,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.tag_badges,
        ru.rn_loc
    from recent_users ru
    left join user_post_agg upa on upa.user_id = ru.user_id
    left join commenter_activity ca on ca.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    where coalesce(upa.questions,0) + coalesce(upa.answers,0) >= 5
),
user_question_window as (
    select
        qm.user_id,
        qm.post_id,
        qm.score,
        qm.viewcount,
        qm.answercount,
        qm.upvotes,
        qm.downvotes,
        qm.favorites,
        qm.bounty_total,
        qm.hours_to_accept,
        qm.creationdate,
        row_number() over (partition by qm.user_id order by qm.score desc nulls last, qm.viewcount desc nulls last, qm.post_id) as rn_q_best,
        row_number() over (partition by qm.user_id order by qm.creationdate desc, qm.post_id desc) as rn_q_recent
    from question_metrics qm
),
user_top_question as (
    select
        uqw.user_id,
        uqw.post_id as top_question_id,
        uqw.score as top_q_score,
        uqw.viewcount as top_q_views,
        uqw.answercount as top_q_answers,
        uqw.upvotes as top_q_up,
        uqw.downvotes as top_q_down,
        uqw.favorites as top_q_fav,
        uqw.bounty_total as top_q_bounty,
        uqw.hours_to_accept as top_q_hours_to_accept
    from user_question_window uqw
    where uqw.rn_q_best = 1
),
user_recent_question as (
    select
        uqw.user_id,
        uqw.post_id as recent_question_id,
        uqw.creationdate as recent_question_at
    from user_question_window uqw
    where uqw.rn_q_recent = 1
),
user_joined as (
    select
        qu.*,
        coalesce(ut.tag, '(no tag)') as top_tag,
        lt.users_in_location,
        lt.median_rep,
        lt.avg_rep,
        lt.max_rep
    from qualified_users qu
    left join user_top_tags ut on ut.user_id = qu.user_id and ut.rn_tag = 1
    left join location_rank lt on lt.location_norm = qu.location_norm
),
question_quality_bucket as (
    select
        qm.post_id,
        case
            when coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) >= 50 then 'A+'
            when coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) >= 20 then 'A'
            when coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) >= 5 then 'B'
            when coalesce(qm.upvotes,0) - coalesce(qm.downvotes,0) >= 0 then 'C'
            else 'D'
        end as quality_grade
    from question_metrics qm
),
final_users as (
    select
        uj.*,
        utq.top_question_id,
        utq.top_q_score,
        utq.top_q_views,
        utq.top_q_answers,
        utq.top_q_up,
        utq.top_q_down,
        utq.top_q_fav,
        utq.top_q_bounty,
        utq.top_q_hours_to_accept,
        urq.recent_question_id,
        urq.recent_question_at
    from user_joined uj
    left join user_top_question utq on utq.user_id = uj.user_id
    left join user_recent_question urq on urq.user_id = uj.user_id
),
score_norm as (
    select
        fu.*,
        case when (coalesce(fu.questions,0) + coalesce(fu.answers,0)) = 0 then null
             else cast(coalesce(fu.total_score,0) as numeric) / nullif(cast(coalesce(fu.questions,0) + coalesce(fu.answers,0) as numeric),0)
        end as avg_score_per_post,
        (coalesce(fu.top_q_score,0) - coalesce(fu.top_q_down,0) + coalesce(fu.top_q_up,0)) as top_q_net_signal
    from final_users fu
),
ranked as (
    select
        sn.*,
        dense_rank() over (order by coalesce(sn.reputation,0) desc, coalesce(sn.total_score,0) desc, sn.user_id) as rep_rank_global,
        row_number() over (partition by sn.location_norm order by coalesce(sn.reputation,0) desc, sn.user_id) as rep_rank_by_location,
        percent_rank() over (order by coalesce(sn.avg_score_per_post,0)) as pct_avg_score_per_post
    from score_norm sn
)
select
    r.user_id,
    r.displayname,
    r.location_norm,
    r.signup_year,
    r.reputation,
    r.rep_rank_global,
    r.rep_rank_by_location,
    r.users_in_location,
    r.median_rep,
    r.avg_rep,
    r.max_rep,
    r.questions,
    r.answers,
    r.total_score,
    r.avg_nonzero_score,
    r.avg_score_per_post,
    r.total_views,
    r.closed_posts,
    r.distinct_questions_answered,
    r.comments_count,
    r.avg_comment_score,
    r.badges_total,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.tag_badges,
    r.top_tag,
    r.top_question_id,
    r.top_q_score,
    r.top_q_views,
    r.top_q_answers,
    r.top_q_up,
    r.top_q_down,
    r.top_q_fav,
    r.top_q_bounty,
    r.top_q_hours_to_accept,
    qqb.quality_grade as top_q_quality_grade,
    r.recent_question_id,
    r.recent_question_at,
    r.pct_avg_score_per_post,
    case
        when r.badges_total >= 50 and coalesce(r.top_q_views,0) >= 100000 then 'elite'
        when r.badges_total >= 20 and coalesce(r.top_q_views,0) >= 20000 then 'advanced'
        when coalesce(r.total_score,0) >= 100 then 'intermediate'
        else 'novice'
    end as contributor_tier
from ranked r
left join question_quality_bucket qqb on qqb.post_id = r.top_question_id
where
    (
        r.rep_rank_by_location <= 50
        or r.rep_rank_global <= 500
        or (r.avg_score_per_post is not null and r.pct_avg_score_per_post >= 0.9)
    )
    and (
        r.location_norm is not null
        or r.signup_year >= extract(year from cast('2024-10-01 12:34:56' as timestamp)) - 2
    )
order by
    r.rep_rank_global nulls last,
    r.rep_rank_by_location nulls last,
    r.user_id
limit 1000;