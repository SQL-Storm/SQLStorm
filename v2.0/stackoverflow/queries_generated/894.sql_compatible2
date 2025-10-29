with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.upvotes,
        u.downvotes,
        u.views,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
),
top_n_users as (
    select *
    from recent_users
    where rn <= 500
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
questions as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.favoritecount,
        p.commentcount,
        p.closeddate,
        p.title,
        p.tags
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        p.id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.commentcount
    from posts p
    where p.posttypeid = 2
),
user_q_metrics as (
    select
        q.user_id,
        count(*) as q_count,
        coalesce(sum(case when q.closeddate is not null then 1 else 0 end),0) as q_closed,
        coalesce(sum(q.viewcount),0) as q_views,
        coalesce(sum(q.score),0) as q_score,
        coalesce(sum(q.answercount),0) as q_answers_recv,
        coalesce(sum(q.favoritecount),0) as q_fav,
        coalesce(sum(q.commentcount),0) as q_comments,
        min(q.creationdate) as q_first_date,
        max(q.creationdate) as q_last_date
    from questions q
    group by q.user_id
),
user_a_metrics as (
    select
        a.user_id,
        count(*) as a_count,
        coalesce(sum(a.score),0) as a_score,
        coalesce(sum(a.commentcount),0) as a_comments,
        min(a.creationdate) as a_first_date,
        max(a.creationdate) as a_last_date
    from answers a
    group by a.user_id
),
accepted_answer_flags as (
    select
        a.user_id,
        count(*) as accepted_count
    from answers a
    join posts q on q.id = a.question_id and q.acceptedanswerid = a.id
    group by a.user_id
),
vote_agg as (
    select
        v.userid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_agg as (
    select
        c.userid,
        count(*) as comments_made,
        sum(coalesce(c.score,0)) as comment_score,
        min(c.creationdate) as first_comment_date,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
tag_extract as (
    select
        q.id as question_id,
        q.user_id,
        unnest(string_to_array(substring(q.tags from 2 for char_length(q.tags)-2), '><')) as tag
    from questions q
    where q.tags is not null and char_length(q.tags) > 2
),
user_top_tags as (
    select
        te.user_id,
        te.tag,
        count(*) as tag_uses,
        row_number() over (partition by te.user_id order by count(*) desc, tag asc) as tag_rank
    from tag_extract te
    group by te.user_id, te.tag
),
user_primary_tag as (
    select user_id, tag as primary_tag, tag_uses
    from user_top_tags
    where tag_rank = 1
),
recent_activity as (
    select
        u.id as user_id,
        greatest(
            coalesce(u.lastaccessdate, timestamp 'epoch'),
            coalesce(uqm.q_last_date, timestamp 'epoch'),
            coalesce(uam.a_last_date, timestamp 'epoch'),
            coalesce(ca.last_comment_date, timestamp 'epoch'),
            coalesce(ba.last_badge_date, timestamp 'epoch')
        ) as last_activity
    from users u
    left join user_q_metrics uqm on uqm.user_id = u.id
    left join user_a_metrics uam on uam.user_id = u.id
    left join comment_agg ca on ca.userid = u.id
    left join user_badge_agg ba on ba.userid = u.id
),
user_quality as (
    select
        u.id as user_id,
        case
            when (coalesce(uqm.q_count,0) + coalesce(uam.a_count,0)) = 0 then null
            else round(
                (
                    coalesce(uqm.q_score,0) + coalesce(uam.a_score,0)
                    + 0.5 * coalesce(af.accepted_count,0)
                    + 0.1 * coalesce(uqm.q_views,0) / nullif(coalesce(uqm.q_count,0),0)
                )
                / greatest(1, (coalesce(uqm.q_count,0) + coalesce(uam.a_count,0)))
                , 4
            )
        end as quality_score
    from users u
    left join user_q_metrics uqm on uqm.user_id = u.id
    left join user_a_metrics uam on uam.user_id = u.id
    left join accepted_answer_flags af on af.user_id = u.id
),
dup_links as (
    select
        pl.postid as duplicate_id,
        pl.relatedpostid as original_id,
        pl.creationdate,
        pl.linktypeid
    from postlinks pl
    where pl.linktypeid = 3
),
dup_stats as (
    select
        q.owneruserid as user_id,
        count(*) as dup_marked_questions
    from dup_links d
    join posts q on q.id = d.duplicate_id
    group by q.owneruserid
),
post_edit_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as first_edit_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_date
    from posthistory ph
    group by ph.postid
),
user_edit_agg as (
    select
        p.owneruserid as user_id,
        sum(coalesce(e.edit_events,0)) as edits,
        min(e.first_edit_date) as first_edit_date,
        max(e.last_edit_date) as last_edit_date
    from posts p
    left join post_edit_events e on e.postid = p.id
    group by p.owneruserid
),
activity_union as (
    select u.id as user_id, 'Q' as kind, uqm.q_first_date as first_date, uqm.q_last_date as last_date, uqm.q_count as cnt
    from users u left join user_q_metrics uqm on uqm.user_id = u.id
    union all
    select u.id, 'A', uam.a_first_date, uam.a_last_date, uam.a_count
    from users u left join user_a_metrics uam on uam.user_id = u.id
    union all
    select u.id, 'C', ca.first_comment_date, ca.last_comment_date, ca.comments_made
    from users u left join comment_agg ca on ca.userid = u.id
),
activity_span as (
    select
        au.user_id,
        min(au.first_date) as first_activity,
        max(au.last_date) as last_activity_component,
        sum(coalesce(au.cnt,0)) as total_actions
    from activity_union au
    group by au.user_id
),
final_rank as (
    select
        tu.user_id,
        tu.displayname,
        tu.location,
        tu.reputation,
        coalesce(uqm.q_count,0) as q_count,
        coalesce(uam.a_count,0) as a_count,
        coalesce(af.accepted_count,0) as accepted_answers,
        coalesce(uqm.q_views,0) as q_views,
        coalesce(uqm.q_score,0) + coalesce(uam.a_score,0) as net_post_score,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.favorites_cast,0) as favorites_cast,
        coalesce(ba.total_badges,0) as total_badges,
        coalesce(ba.gold_badges,0) as gold_badges,
        coalesce(ba.silver_badges,0) as silver_badges,
        coalesce(ba.bronze_badges,0) as bronze_badges,
        coalesce(ba.tag_badges,0) as tag_badges,
        coalesce(ca.comments_made,0) as comments_made,
        coalesce(ds.dup_marked_questions,0) as dup_marked_questions,
        coalesce(ea.edits,0) as edits_made,
        up.primary_tag,
        up.tag_uses as primary_tag_uses,
        ra.last_activity,
        aspan.first_activity,
        aspan.last_activity_component,
        aspan.total_actions,
        uq.quality_score,
        (
            0.40 * coalesce(uq.quality_score, 0)
            + 0.15 * ln(1 + coalesce(uqm.q_views,0))
            + 0.20 * ln(1 + coalesce(uam.a_count,0) + coalesce(uqm.q_count,0))
            + 0.05 * coalesce(ba.gold_badges,0)
            + 0.03 * coalesce(ba.silver_badges,0)
            + 0.02 * coalesce(ba.bronze_badges,0)
            + 0.05 * ln(1 + coalesce(af.accepted_count,0))
            - 0.03 * coalesce(ds.dup_marked_questions,0)
            - 0.02 * greatest(0, coalesce(va.downvotes_cast,0) - coalesce(va.upvotes_cast,0))
            + 0.03 * ln(1 + coalesce(ea.edits,0))
        ) as benchmark_score
    from top_n_users tu
    left join user_q_metrics uqm on uqm.user_id = tu.user_id
    left join user_a_metrics uam on uam.user_id = tu.user_id
    left join accepted_answer_flags af on af.user_id = tu.user_id
    left join vote_agg va on va.userid = tu.user_id
    left join user_badge_agg ba on ba.userid = tu.user_id
    left join comment_agg ca on ca.userid = tu.user_id
    left join dup_stats ds on ds.user_id = tu.user_id
    left join user_edit_agg ea on ea.user_id = tu.user_id
    left join user_primary_tag up on up.user_id = tu.user_id
    left join recent_activity ra on ra.user_id = tu.user_id
    left join activity_span aspan on aspan.user_id = tu.user_id
    left join user_quality uq on uq.user_id = tu.user_id
),
ranked as (
    select
        fr.user_id,
        fr.displayname,
        fr.location,
        fr.reputation,
        fr.q_count,
        fr.a_count,
        fr.accepted_answers,
        fr.q_views,
        fr.net_post_score,
        fr.upvotes_cast,
        fr.downvotes_cast,
        fr.favorites_cast,
        fr.total_badges,
        fr.gold_badges,
        fr.silver_badges,
        fr.bronze_badges,
        fr.tag_badges,
        fr.comments_made,
        fr.dup_marked_questions,
        fr.edits_made,
        fr.primary_tag,
        fr.primary_tag_uses,
        fr.last_activity,
        fr.first_activity,
        fr.last_activity_component,
        fr.total_actions,
        fr.quality_score,
        fr.benchmark_score,
        rank() over (order by fr.benchmark_score desc, fr.reputation desc, fr.user_id desc) as rnk,
        dense_rank() over (order by coalesce(fr.gold_badges,0)*3 + coalesce(fr.silver_badges,0)*2 + coalesce(fr.bronze_badges,0) desc) as badge_rank,
        row_number() over (partition by coalesce(lower(nullif(trim(fr.location), '')), 'unknown')
                           order by fr.benchmark_score desc, fr.reputation desc) as geo_rownum,
        (coalesce(fr.gold_badges,0)*3 + coalesce(fr.silver_badges,0)*2 + coalesce(fr.bronze_badges,0)) as ba_score
    from final_rank fr
)
select
    r.user_id,
    r.displayname,
    r.location,
    r.reputation,
    r.q_count,
    r.a_count,
    r.accepted_answers,
    r.q_views,
    r.net_post_score,
    r.upvotes_cast,
    r.downvotes_cast,
    r.favorites_cast,
    r.total_badges,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.tag_badges,
    r.comments_made,
    r.dup_marked_questions,
    r.edits_made,
    coalesce(r.primary_tag, '(none)') as primary_tag,
    coalesce(r.primary_tag_uses, 0) as primary_tag_uses,
    r.first_activity,
    r.last_activity,
    r.last_activity_component,
    r.total_actions,
    r.quality_score,
    r.benchmark_score,
    r.rnk as global_rank,
    r.badge_rank,
    r.geo_rownum as rank_within_location,
    case
        when r.primary_tag is null then null
        else concat(r.primary_tag, ' (', cast(r.primary_tag_uses as varchar), ')')
    end as primary_tag_label
from ranked r
where
    (
        r.last_activity > timestamp '2024-10-01 12:34:56' - interval '365 days'
        or coalesce(r.quality_score,0) > 1.5
        or r.reputation >= 5000
    )
    and (
        lower(coalesce(nullif(trim(r.location), ''), 'unknown')) not like '%test%'
        and lower(coalesce(nullif(trim(r.location), ''), 'unknown')) not like '%dummy%'
    )
order by r.benchmark_score desc, r.reputation desc, r.user_id desc
limit 200;