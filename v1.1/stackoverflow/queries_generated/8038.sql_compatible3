with
recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.owneruserid,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        coalesce(p.commentcount, 0) as commentcount
    from posts p
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_creation,
        u.location,
        u.upvotes,
        u.downvotes,
        u.websiteurl,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.upvotes, u.downvotes, u.websiteurl
),
post_votes as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (10,12)) as deletion_flags
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by v.postid
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_date,
        sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
        sum(case when c.score < 0 then 1 else 0 end) as neg_comments
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by c.postid
),
duplicate_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by pl.postid
),
close_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopened_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_date,
        mode() within group (order by cast(nullif(regexp_replace(ph.comment, '[^0-9]', '', 'g'), '') as integer)) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '[0-9]') as modal_close_reason_id
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
      and ph.posthistorytypeid in (10,11)
    group by ph.postid
),
tag_expansion as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2,0)), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
tag_quality as (
    select
        te.post_id,
        count(*) as tag_count,
        sum(t.count) as global_tag_popularity,
        avg(t.count) as avg_tag_popularity,
        sum(case when t.ismoderatoronly then 1 else 0 end) as mod_only_tags,
        sum(case when t.isrequired then 1 else 0 end) as required_tags
    from tag_expansion te
    left join tags t on lower(t.tagname) = lower(te.tag)
    group by te.post_id
),
answer_latency as (
    select
        q.id as question_id,
        min(a.creationdate) - q.creationdate as time_to_first_answer,
        count(a.id) as total_answers,
        max(a.score) as max_answer_score,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted
    from posts q
    left join posts a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by q.id
),
post_engagement as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.title,
        rp.tags,
        rp.answercount,
        rp.favoritecount,
        coalesce(pv.upvotes,0) as upvotes,
        coalesce(pv.downvotes,0) as downvotes,
        coalesce(pv.bounty_started,0) as bounty_started,
        coalesce(pv.bounty_awarded,0) as bounty_awarded,
        coalesce(pv.deletion_flags,0) as deletion_flags,
        coalesce(cs.comment_count,0) as comment_count,
        cs.last_comment_date,
        coalesce(cs.pos_comments,0) as pos_comments,
        coalesce(cs.neg_comments,0) as neg_comments,
        coalesce(dl.dup_count,0) as dup_count,
        coalesce(dl.linked_count,0) as linked_count,
        dl.last_link_date,
        coalesce(ce.closed_events,0) as closed_events,
        coalesce(ce.reopened_events,0) as reopened_events,
        ce.last_closed_date,
        ce.last_reopened_date,
        ce.modal_close_reason_id,
        tq.tag_count,
        tq.global_tag_popularity,
        tq.avg_tag_popularity,
        tq.mod_only_tags,
        tq.required_tags,
        al.time_to_first_answer,
        al.total_answers,
        al.max_answer_score,
        al.has_accepted
    from recent_posts rp
    left join post_votes pv on pv.postid = rp.id
    left join comment_stats cs on cs.postid = rp.id
    left join duplicate_links dl on dl.postid = rp.id
    left join close_events ce on ce.postid = rp.id
    left join tag_quality tq on tq.post_id = rp.id
    left join answer_latency al on al.question_id = rp.id
),
user_post_summary as (
    select
        p.owneruserid as user_id,
        count(*) as total_posts,
        count(*) filter (where p.posttypeid = 1) as total_questions,
        count(*) filter (where p.posttypeid = 2) as total_answers,
        sum(p.score) as total_score,
        avg(p.score) as avg_post_score,
        max(p.creationdate) as last_post_date,
        sum(coalesce(pe.upvotes,0)) as sum_upvotes,
        sum(coalesce(pe.downvotes,0)) as sum_downvotes,
        sum(coalesce(pe.comment_count,0)) as sum_comments,
        sum(coalesce(pe.favoritecount,0)) as sum_favorites,
        sum(coalesce(pe.viewcount,0)) as sum_views,
        sum(coalesce(pe.dup_count,0)) as sum_dups_received
    from posts p
    left join post_engagement pe on pe.post_id = p.id
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by p.owneruserid
),
normalized_engagement as (
    select
        pe.post_id,
        pe.posttypeid,
        pe.creationdate,
        pe.score,
        pe.viewcount,
        pe.title,
        pe.tags,
        pe.answercount,
        pe.favoritecount,
        pe.upvotes,
        pe.downvotes,
        pe.bounty_started,
        pe.bounty_awarded,
        pe.deletion_flags,
        pe.comment_count,
        pe.last_comment_date,
        pe.pos_comments,
        pe.neg_comments,
        pe.dup_count,
        pe.linked_count,
        pe.last_link_date,
        pe.closed_events,
        pe.reopened_events,
        pe.last_closed_date,
        pe.last_reopened_date,
        pe.modal_close_reason_id,
        pe.tag_count,
        pe.global_tag_popularity,
        pe.avg_tag_popularity,
        pe.mod_only_tags,
        pe.required_tags,
        pe.time_to_first_answer,
        pe.total_answers,
        pe.max_answer_score,
        pe.has_accepted,
        case
            when pe.viewcount > 0 then (pe.upvotes - pe.downvotes) / NULLIF(pe.viewcount,0)
            else null
        end as vote_view_ratio,
        case
            when coalesce(pe.tag_count,0) > 0 then pe.score / NULLIF(pe.tag_count,0)
            else pe.score
        end as score_per_tag,
        case
            when pe.favoritecount is null or pe.favoritecount = 0 then null
            else pe.viewcount / NULLIF(pe.favoritecount,0)
        end as views_per_favorite,
        case
            when pe.total_answers > 0 then pe.score / NULLIF(pe.total_answers,0)
            else null
        end as score_per_answer
    from post_engagement pe
),
ranked_posts as (
    select
        ne.post_id,
        ne.posttypeid,
        ne.creationdate,
        ne.score,
        ne.viewcount,
        ne.title,
        ne.tags,
        ne.answercount,
        ne.favoritecount,
        ne.upvotes,
        ne.downvotes,
        ne.bounty_started,
        ne.bounty_awarded,
        ne.deletion_flags,
        ne.comment_count,
        ne.last_comment_date,
        ne.pos_comments,
        ne.neg_comments,
        ne.dup_count,
        ne.linked_count,
        ne.last_link_date,
        ne.closed_events,
        ne.reopened_events,
        ne.last_closed_date,
        ne.last_reopened_date,
        ne.modal_close_reason_id,
        ne.tag_count,
        ne.global_tag_popularity,
        ne.avg_tag_popularity,
        ne.mod_only_tags,
        ne.required_tags,
        ne.time_to_first_answer,
        ne.total_answers,
        ne.max_answer_score,
        ne.has_accepted,
        ne.vote_view_ratio,
        ne.score_per_tag,
        ne.views_per_favorite,
        ne.score_per_answer,
        dense_rank() over (order by coalesce(ne.vote_view_ratio, -1e9) desc, ne.score desc, ne.viewcount desc) as r_vote_efficiency,
        row_number() over (partition by ne.posttypeid order by ne.score desc, ne.viewcount desc) as r_top_by_type,
        ntile(10) over (order by coalesce(ne.views_per_favorite, 1e9)) as decile_views_per_fav_low_to_high,
        ntile(10) over (order by coalesce(ne.score_per_tag, -1e9) desc) as decile_score_per_tag_high_to_low,
        sum(ne.viewcount) over (order by ne.creationdate rows between unbounded preceding and current row) as running_views_by_time
    from normalized_engagement ne
),
user_enriched as (
    select
        ups.user_id,
        ua.displayname,
        ua.reputation,
        ua.user_creation,
        ua.location,
        ua.websiteurl,
        ua.upvotes as user_upvotes,
        ua.downvotes as user_downvotes,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.last_badge_date,
        ups.total_posts,
        ups.total_questions,
        ups.total_answers,
        ups.total_score,
        ups.avg_post_score,
        ups.last_post_date,
        ups.sum_upvotes,
        ups.sum_downvotes,
        ups.sum_comments,
        ups.sum_favorites,
        ups.sum_views,
        ups.sum_dups_received
    from user_post_summary ups
    left join user_activity ua on ua.user_id = ups.user_id
),
top_users as (
    select
        ue.*,
        dense_rank() over (order by coalesce(ue.total_score,0) + coalesce(ue.sum_upvotes,0) - coalesce(ue.sum_downvotes,0) desc) as r_overall_contrib
    from user_enriched ue
),
post_anomalies as (
    select
        rp.id as post_id,
        case
            when rp.score <= 0 and coalesce(pv.upvotes,0) >= 5 then 'low-score-high-upvotes'
            when rp.viewcount >= 10000 and coalesce(cs.comment_count,0) = 0 then 'high-views-no-discussion'
            when coalesce(dl.dup_count,0) >= 3 then 'many-duplicates'
            when coalesce(ce.closed_events,0) >= 2 and coalesce(ce.reopened_events,0) = 0 then 'frequently-closed'
            else null
        end as anomaly_type
    from recent_posts rp
    left join post_votes pv on pv.postid = rp.id
    left join comment_stats cs on cs.postid = rp.id
    left join duplicate_links dl on dl.postid = rp.id
    left join close_events ce on ce.postid = rp.id
    where (
        (rp.score <= 0 and coalesce(pv.upvotes,0) >= 5) or
        (rp.viewcount >= 10000 and coalesce(cs.comment_count,0) = 0) or
        (coalesce(dl.dup_count,0) >= 3) or
        (coalesce(ce.closed_events,0) >= 2 and coalesce(ce.reopened_events,0) = 0)
    )
),
final_union as (
    select
        'post' as entity_type,
        cast(rp.post_id as varchar) as entity_id,
        lower(coalesce(rp.title, '[no-title]')) as label,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.upvotes,
        rp.downvotes,
        rp.favoritecount,
        rp.dup_count,
        rp.linked_count,
        rp.closed_events,
        rp.reopened_events,
        rp.modal_close_reason_id,
        rp.tag_count,
        rp.global_tag_popularity,
        rp.avg_tag_popularity,
        rp.mod_only_tags,
        rp.required_tags,
        rp.time_to_first_answer,
        rp.total_answers,
        rp.max_answer_score,
        rp.has_accepted,
        rp.vote_view_ratio,
        rp.score_per_tag,
        rp.views_per_favorite,
        rp.score_per_answer,
        rp.r_vote_efficiency,
        rp.r_top_by_type,
        rp.decile_views_per_fav_low_to_high,
        rp.decile_score_per_tag_high_to_low,
        rp.running_views_by_time,
        CAST(NULL AS integer) as user_id,
        CAST(NULL AS varchar) as user_displayname,
        CAST(NULL AS integer) as user_reputation,
        CAST(NULL AS integer) as user_total_posts,
        CAST(NULL AS integer) as user_total_score,
        pa.anomaly_type
    from ranked_posts rp
    left join post_anomalies pa on pa.post_id = rp.post_id

    union all

    select
        'user' as entity_type,
        cast(tu.user_id as varchar) as entity_id,
        coalesce(tu.displayname, '[unknown-user]') as label,
        tu.user_creation as creationdate,
        tu.total_score as score,
        tu.sum_views as viewcount,
        tu.user_upvotes as upvotes,
        tu.user_downvotes as downvotes,
        tu.sum_favorites as favoritecount,
        tu.sum_dups_received as dup_count,
        CAST(NULL AS integer) as linked_count,
        CAST(NULL AS integer) as closed_events,
        CAST(NULL AS integer) as reopened_events,
        CAST(NULL AS integer) as modal_close_reason_id,
        CAST(NULL AS integer) as tag_count,
        CAST(NULL AS bigint) as global_tag_popularity,
        CAST(NULL AS numeric) as avg_tag_popularity,
        CAST(NULL AS integer) as mod_only_tags,
        CAST(NULL AS integer) as required_tags,
        CAST(NULL AS interval) as time_to_first_answer,
        CAST(NULL AS integer) as total_answers,
        CAST(NULL AS integer) as max_answer_score,
        CAST(NULL AS integer) as has_accepted,
        CAST(NULL AS numeric) as vote_view_ratio,
        CAST(NULL AS numeric) as score_per_tag,
        CAST(NULL AS numeric) as views_per_favorite,
        CAST(NULL AS numeric) as score_per_answer,
        CAST(NULL AS bigint) as r_vote_efficiency,
        CAST(NULL AS bigint) as r_top_by_type,
        CAST(NULL AS integer) as decile_views_per_fav_low_to_high,
        CAST(NULL AS integer) as decile_score_per_tag_high_to_low,
        CAST(NULL AS bigint) as running_views_by_time,
        tu.user_id,
        tu.displayname as user_displayname,
        tu.reputation as user_reputation,
        tu.total_posts as user_total_posts,
        tu.total_score as user_total_score,
        CAST(NULL AS varchar) as anomaly_type
    from top_users tu
    where tu.r_overall_contrib <= 500
)
select *
from final_union fu
where
    (
        fu.entity_type = 'post'
        and (
            fu.score >= 5
            or coalesce(fu.upvotes,0) - coalesce(fu.downvotes,0) >= 3
            or fu.anomaly_type is not null
        )
    )
    or
    (
        fu.entity_type = 'user'
        and coalesce(fu.user_reputation,0) >= 1000
    )
order by
    fu.entity_type,
    coalesce(cast(fu.r_vote_efficiency as numeric), 0) desc,
    fu.score desc,
    fu.viewcount desc
limit 1000;