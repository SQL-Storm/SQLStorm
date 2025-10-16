with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where coalesce(u.displayname, '') <> ''
),
top_recent_users as (
    select *
    from recent_users
    where rn <= 500
),
user_posts as (
    select
        p.id as post_id,
        coalesce(p.owneruserid, p.owneruserid) as owner_user_id,
        p.owneruserid as owner_user_id_fix,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        p.lastactivitydate,
        p.commentcount
    from posts p
),
answers_with_parent as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.score as answer_score,
        a.creationdate as answer_date,
        qa.owneruserid as asker_id,
        qa.score as question_score,
        qa.viewcount as question_views,
        qa.title as question_title,
        qa.tags as question_tags,
        qa.creationdate as question_date
    from posts a
    join posts qa on qa.id = a.parentid and a.posttypeid = 2 and qa.posttypeid = 1
),
user_activity as (
    select
        u.user_id,
        count(*) filter (where p.posttypeid = 1) as questions_count,
        count(*) filter (where p.posttypeid = 2) as answers_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        max(p.lastactivitydate) as last_post_activity
    from top_recent_users u
    left join posts p on p.owneruserid = u.user_id
    group by u.user_id
),
tag_exploded_questions as (
    select
        q.id as question_id,
        lower(trim(tg)) as tagname_norm
    from posts q
    cross join lateral (
        select unnest(
            case
                when q.posttypeid = 1 and q.tags is not null and length(q.tags) >= 2
                then string_to_array(substring(q.tags from 2 for length(q.tags)-2), '><')
                else array[]::text[]
            end
        ) as tg
    ) t
    where q.posttypeid = 1
),
top_user_tags as (
    select
        p.owneruserid as user_id,
        te.tagname_norm,
        count(*) as tag_q_count,
        sum(p.score) as tag_q_score
    from posts p
    join tag_exploded_questions te on te.question_id = p.id and p.posttypeid = 1
    group by p.owneruserid, te.tagname_norm
),
user_top3_tags as (
    select user_id, tagname_norm, tag_q_count, tag_q_score,
           row_number() over (partition by user_id order by tag_q_count desc, tag_q_score desc, tagname_norm) as rn
    from top_user_tags
),
recent_comments as (
    select
        c.userid as commenter_id,
        c.postid,
        count(*) as comment_cnt,
        max(c.creationdate) as last_comment_at,
        sum(coalesce(c.score,0)) as comment_score_sum
    from comments c
    group by c.userid, c.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    group by v.postid
),
duplicates as (
    select
        pl.postid as dup_question_id,
        pl.relatedpostid as original_question_id,
        min(pl.creationdate) as first_link_at,
        count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
closed_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        max(ph.creationdate) as last_closed_at,
        max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid = 10
    group by ph.postid
),
user_badges as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_cnt,
        sum(case when b.class = 2 then 1 else 0 end) as silver_cnt,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_cnt,
        sum(case when b.tagbased then 1 else 0 end) as tag_badge_cnt,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
normalized_locations as (
    select
        u.user_id,
        nullif(trim(regexp_replace(coalesce(u.location, ''), '\s+', ' ', 'g')), '') as location_norm
    from top_recent_users u
),
location_groups as (
    select
        nl.location_norm,
        count(distinct nl.user_id) as users_in_location
    from normalized_locations nl
    group by nl.location_norm
),
post_quality as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.commentcount,
        va.upvotes,
        va.downvotes,
        (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) as net_votes,
        case
            when p.posttypeid = 1 then greatest(1, coalesce(p.viewcount,0))
            else 1
        end as denom,
        (coalesce(p.score,0) + (coalesce(va.upvotes,0) * 0.5) - (coalesce(va.downvotes,0) * 0.75)) / case when p.posttypeid = 1 then greatest(1, coalesce(p.viewcount,0)) else 1 end as quality_metric
    from posts p
    left join vote_agg va on va.postid = p.id
),
user_quality as (
    select
        pq.user_id,
        avg(pq.quality_metric) filter (where pq.posttypeid = 1) as avg_q_quality,
        avg(pq.quality_metric) filter (where pq.posttypeid = 2) as avg_a_quality,
        percentile_cont(0.9) within group (order by pq.quality_metric) as p90_quality,
        count(*) as posts_considered
    from post_quality pq
    group by pq.user_id
),
question_lifecycle as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as asked_at,
        q.acceptedanswerid,
        min(a.creationdate) filter (where a.parentid = q.id) as first_answer_at,
        count(a.id) filter (where a.parentid = q.id) as total_answers,
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        cr.first_closed_at,
        cr.last_closed_at,
        d.dup_link_count,
        d.original_question_id
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    left join closed_reasons cr on cr.postid = q.id
    left join duplicates d on d.dup_question_id = q.id
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.acceptedanswerid, cr.first_closed_at, cr.last_closed_at, d.dup_link_count, d.original_question_id
),
recent_hot_candidates as (
    select
        ql.question_id,
        ql.asker_id,
        ql.asked_at,
        ql.total_answers,
        ql.has_accepted,
        ql.first_closed_at,
        ql.dup_link_count,
        p.viewcount,
        p.score,
        p.title,
        p.tags,
        (extract(epoch from (timestamp '2024-10-01 12:34:56' - ql.asked_at)) / 3600.0) as age_hours,
        (coalesce(p.score,0) + coalesce(ql.total_answers,0) * 0.3 + coalesce(p.viewcount,0) / 1000.0) as hotness
    from question_lifecycle ql
    join posts p on p.id = ql.question_id
    where ql.asked_at >= timestamp '2024-10-01 12:34:56' - interval '365 days'
),
user_engagement as (
    select
        u.user_id,
        count(distinct rhc.question_id) as questions_last_year,
        sum(case when rhc.has_accepted = 1 then 1 else 0 end) as accepted_last_year,
        sum(coalesce(rhc.total_answers,0)) as answers_on_my_questions_last_year,
        avg(rhc.hotness) as avg_question_hotness_last_year
    from top_recent_users u
    left join recent_hot_candidates rhc on rhc.asker_id = u.user_id
    group by u.user_id
),
mix_set as (
    select u.user_id, 'post_owner' as src, p.id as post_id
    from top_recent_users u
    join posts p on p.owneruserid = u.user_id
    union all
    select u.user_id, 'commented' as src, c.postid
    from top_recent_users u
    join comments c on c.userid = u.user_id
),
distinct_activity_posts as (
    select user_id, count(distinct post_id) as distinct_posts_touched
    from mix_set
    group by user_id
),
ranked_questions as (
    select
        rhc.*,
        row_number() over (partition by rhc.asker_id order by rhc.hotness desc, rhc.viewcount desc, rhc.score desc, rhc.question_id) as rq
    from recent_hot_candidates rhc
),
final as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nl.location_norm, '(unknown)') as location_norm,
        lg.users_in_location,
        ua.questions_count,
        ua.answers_count,
        ua.total_post_score,
        ua.total_question_views,
        ua.last_post_activity,
        uq.avg_q_quality,
        uq.avg_a_quality,
        uq.p90_quality,
        uq.posts_considered,
        coalesce(ub.gold_cnt,0) as gold_badges,
        coalesce(ub.silver_cnt,0) as silver_badges,
        coalesce(ub.bronze_cnt,0) as bronze_badges,
        coalesce(ub.tag_badge_cnt,0) as tag_badges,
        ub.last_badge_at,
        ue.questions_last_year,
        ue.accepted_last_year,
        ue.answers_on_my_questions_last_year,
        ue.avg_question_hotness_last_year,
        dap.distinct_posts_touched,
        string_agg(case when utt.rn <= 3 then utt.tagname_norm else null end, ', ' order by utt.rn) filter (where utt.rn <= 3) as top3_tags,
        rq.question_id as top_question_id,
        rq.title as top_question_title,
        rq.hotness as top_question_hotness,
        rq.viewcount as top_question_views,
        rq.score as top_question_score,
        rq.tags as top_question_tags
    from top_recent_users u
    left join normalized_locations nl on nl.user_id = u.user_id
    left join location_groups lg on lg.location_norm = nl.location_norm
    left join user_activity ua on ua.user_id = u.user_id
    left join user_quality uq on uq.user_id = u.user_id
    left join user_badges ub on ub.user_id = u.user_id
    left join user_engagement ue on ue.user_id = u.user_id
    left join distinct_activity_posts dap on dap.user_id = u.user_id
    left join user_top3_tags utt on utt.user_id = u.user_id and utt.rn <= 3
    left join ranked_questions rq on rq.asker_id = u.user_id and rq.rq = 1
    group by
        u.user_id, u.displayname, u.reputation, u.creationdate,
        nl.location_norm, lg.users_in_location,
        ua.questions_count, ua.answers_count, ua.total_post_score, ua.total_question_views, ua.last_post_activity,
        uq.avg_q_quality, uq.avg_a_quality, uq.p90_quality, uq.posts_considered,
        ub.gold_cnt, ub.silver_cnt, ub.bronze_cnt, ub.tag_badge_cnt, ub.last_badge_at,
        ue.questions_last_year, ue.accepted_last_year, ue.answers_on_my_questions_last_year, ue.avg_question_hotness_last_year,
        dap.distinct_posts_touched,
        rq.question_id, rq.title, rq.hotness, rq.viewcount, rq.score, rq.tags
)
select *
from final
where
    coalesce(reputation,0) >= 1
    and (avg_q_quality is not null or avg_a_quality is not null)
    and (questions_count + answers_count) > 0
    and (
        location_norm not ilike '%test%' or users_in_location > 1
    )
order by
    reputation desc,
    coalesce(avg_q_quality, avg_a_quality) desc,
    total_post_score desc,
    user_id
limit 200;