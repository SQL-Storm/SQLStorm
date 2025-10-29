-- {"query": "887.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2726}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_post_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        max(p.lastactivitydate) as last_activity_at,
        count(*) filter (where p.closeddate is not null) as closed_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answerers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_answers,
        sum(coalesce(q.score,0)) as sum_scores_of_questions_answered
    from posts a
    join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
    where q.acceptedanswerid = a.id
    group by a.owneruserid
),
vote_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_agg as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_at,
        count(*) filter (where length(coalesce(c.text,'')) > 280) as long_comments
    from comments c
    where c.userid is not null
    group by c.userid
),
badges_recent as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
question_tag_stats as (
    select
        q.owneruserid as user_id,
        count(*) as tagged_questions,
        sum(array_length(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'), 1)) as total_tag_count,
        avg(array_length(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'), 1)) as avg_tags_per_q
    from posts q
    where q.posttypeid = 1 and q.owneruserid is not null and q.tags is not null and q.tags like '<%>'
    group by q.owneruserid
),
postlink_dups as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    group by pl.postid
),
closed_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        min(
            case
                when ph.posthistorytypeid = 10 then
                    case
                        when trim(ph.comment) ~ '^[0-9]+$' then ph.comment
                        else null
                    end
                else null
            end
        ) as close_reason_id_text
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
post_quality as (
    select
        p.id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.score,
        p.viewcount,
        coalesce(pl.duplicate_links, 0) as duplicate_links,
        cr.first_closed_at,
        cr.close_reason_id_text,
        case
            when p.posttypeid = 1 then
                coalesce(p.viewcount,0) * 0.002
                + coalesce(p.score,0) * 1.0
                - case when cr.first_closed_at is not null then 2 else 0 end
                - least(coalesce(pl.duplicate_links,0), 5) * 0.5
            when p.posttypeid = 2 then
                coalesce(p.score,0) * 1.2
            else 0
        end as quality_score
    from posts p
    left join postlink_dups pl on pl.postid = p.id
    left join closed_reasons cr on cr.postid = p.id
    where p.owneruserid is not null and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_quality as (
    select
        pq.user_id,
        avg(pq.quality_score) as avg_quality_score,
        -- use percentile_disc as more portable; approximate 90th percentile
        percentile_disc(0.9) within group (order by pq.quality_score) as p90_quality,
        sum(case when pq.posttypeid = 1 then 1 else 0 end) as q_posts,
        sum(case when pq.posttypeid = 2 then 1 else 0 end) as a_posts
    from post_quality pq
    group by pq.user_id
),
activity_rank as (
    select
        ru.user_id,
        dense_rank() over (order by coalesce(upa.q_count,0) + coalesce(upa.a_count,0) desc, coalesce(upa.total_post_score,0) desc) as dr_activity,
        dense_rank() over (order by coalesce(va.upvotes_cast,0) - coalesce(va.downvotes_cast,0) desc) as dr_votes,
        dense_rank() over (order by coalesce(ba.badges_total,0) desc) as dr_badges,
        dense_rank() over (order by coalesce(uq.avg_quality_score,0) desc) as dr_quality
    from recent_users ru
    left join user_post_activity upa on upa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join badges_recent ba on ba.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    group by ru.user_id, upa.q_count, upa.a_count, upa.total_post_score, va.upvotes_cast, va.downvotes_cast, ba.badges_total, uq.avg_quality_score
),
final_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.cohort_month,
        ru.rn_global,
        upa.q_count,
        upa.a_count,
        upa.total_post_score,
        upa.total_question_views,
        upa.last_activity_at,
        upa.closed_posts,
        aa.accepted_answers,
        aa.sum_scores_of_questions_answered,
        va.upvotes_cast,
        va.downvotes_cast,
        va.favorites_cast,
        va.bounties_started,
        va.bounty_total,
        ca.comments_made,
        ca.comment_score,
        ca.last_comment_at,
        ca.long_comments,
        ba.badges_total,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        ba.tag_badges,
        ba.last_badge_at,
        qts.tagged_questions,
        qts.total_tag_count,
        qts.avg_tags_per_q,
        uq.avg_quality_score,
        uq.p90_quality,
        uq.q_posts,
        uq.a_posts
    from recent_users ru
    left join user_post_activity upa on upa.user_id = ru.user_id
    left join accepted_answerers aa on aa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join comment_agg ca on ca.user_id = ru.user_id
    left join badges_recent ba on ba.user_id = ru.user_id
    left join question_tag_stats qts on qts.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
),
cohort_summaries as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        avg(reputation) as avg_rep,
        percentile_disc(0.5) within group (order by coalesce(avg_quality_score,0)) as median_quality,
        sum(coalesce(q_count,0) + coalesce(a_count,0)) as total_posts,
        sum(coalesce(comments_made,0)) as total_comments
    from final_users
    group by cohort_month
),
string_flags as (
    select
        fu.user_id,
        case
            when fu.location ilike '%remote%' or fu.location ilike '%anywhere%' then 'remote'
            when fu.location ~* '^[A-Za-z ,.-]{0,100}$' and fu.location is not null then 'textual'
            when fu.location is null or btrim(coalesce(fu.location,'')) = '' then 'empty'
            else 'other'
        end as location_flag,
        case
            when fu.websiteurl like '%github.com%' then 'github'
            when fu.websiteurl like '%linkedin.com%' then 'linkedin'
            when fu.websiteurl like '%stackoverflow.com/users%' then 'so-profile'
            else 'other'
        end as web_flag
    from final_users fu
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.cohort_month,
    fu.q_count,
    fu.a_count,
    fu.accepted_answers,
    fu.total_post_score,
    fu.total_question_views,
    fu.closed_posts,
    fu.upvotes_cast,
    fu.downvotes_cast,
    fu.favorites_cast,
    fu.bounties_started,
    fu.bounty_total,
    fu.comments_made,
    fu.comment_score,
    fu.badges_total,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.tag_badges,
    fu.tagged_questions,
    fu.total_tag_count,
    fu.avg_tags_per_q,
    fu.avg_quality_score,
    fu.p90_quality,
    fu.q_posts,
    fu.a_posts,
    sf.location_flag,
    sf.web_flag,
    ar.dr_activity,
    ar.dr_votes,
    ar.dr_badges,
    ar.dr_quality,
    cs.users_in_cohort,
    cs.avg_rep as cohort_avg_rep,
    cs.median_quality as cohort_median_quality,
    date_part('day', cast('2024-10-01 12:34:56' as timestamp) - coalesce(fu.last_activity_at, fu.creationdate)) * 1 as days_since_last_activity,
    case
        when coalesce(fu.a_count,0) > 0 then round(cast(coalesce(fu.accepted_answers,0) as numeric) / nullif(fu.a_count,0), 4)
        else null
    end as accept_rate,
    case
        when coalesce(fu.q_count,0) > 0 then round(cast(coalesce(fu.total_question_views,0) as numeric) / nullif(fu.q_count,0), 2)
        else null
    end as avg_views_per_q,
    case when fu.rn_global <= 200 then 'top200_recent_by_created' else 'rest' end as recent_bucket
from final_users fu
left join string_flags sf on sf.user_id = fu.user_id
left join activity_rank ar on ar.user_id = fu.user_id
left join cohort_summaries cs on cs.cohort_month = fu.cohort_month
where
    coalesce(fu.q_count,0) + coalesce(fu.a_count,0) > 0
    and (coalesce(fu.avg_quality_score,0) > 0 or coalesce(fu.badges_total,0) > 0)
    and not (
        (fu.displayname ilike '%test%' or fu.displayname ilike '%dummy%' or fu.displayname ilike '%bot%') and fu.reputation < 100
    )
group by
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.cohort_month,
    fu.q_count,
    fu.a_count,
    fu.accepted_answers,
    fu.total_post_score,
    fu.total_question_views,
    fu.closed_posts,
    fu.upvotes_cast,
    fu.downvotes_cast,
    fu.favorites_cast,
    fu.bounties_started,
    fu.bounty_total,
    fu.comments_made,
    fu.comment_score,
    fu.badges_total,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.tag_badges,
    fu.tagged_questions,
    fu.total_tag_count,
    fu.avg_tags_per_q,
    fu.avg_quality_score,
    fu.p90_quality,
    fu.q_posts,
    fu.a_posts,
    sf.location_flag,
    sf.web_flag,
    ar.dr_activity,
    ar.dr_votes,
    ar.dr_badges,
    ar.dr_quality,
    cs.users_in_cohort,
    cs.avg_rep,
    cs.median_quality,
    fu.last_activity_at,
    fu.creationdate,
    fu.rn_global,
    fu.accepted_answers,
    fu.total_question_views
order by
    ar.dr_quality nulls last,
    fu.avg_quality_score desc,
    fu.accepted_answers desc,
    fu.reputation desc
limit 500;