-- {"query": "827.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3728} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rn_in_cohort
    from users u
    where u.creationdate >= now() - interval '5 years'
),
user_badge_agg as (
    select
        b.userid,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
posts_expanded as (
    select
        p.id,
        p.owneruserid,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.title,
        p.tags,
        case when p.posttypeid = 1 then 'Question'
             when p.posttypeid = 2 then 'Answer'
             else 'Other'
        end as post_type,
        string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_array
    from posts p
    where p.creationdate >= now() - interval '5 years'
),
user_post_metrics as (
    select
        pe.owneruserid as user_id,
        count(*) filter (where pe.posttypeid = 1) as questions,
        count(*) filter (where pe.posttypeid = 2) as answers,
        count(*) filter (where pe.posttypeid not in (1,2)) as other_posts,
        coalesce(sum(pe.score),0) as total_score,
        coalesce(sum(pe.viewcount),0) as total_views,
        coalesce(sum(pe.commentcount),0) as total_comments,
        coalesce(sum(pe.favoritecount),0) as total_favs,
        max(pe.closeddate) as last_closed_date,
        avg(nullif(pe.answercount,0)) as avg_answercount_nonzero
    from posts_expanded pe
    where pe.owneruserid is not null
    group by pe.owneruserid
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(*) filter (where v.votetypeid in (8,9)) as bounties,
        sum(coalesce(v.bountyamount,0)) as bounty_amount
    from votes v
    where v.creationdate >= now() - interval '5 years'
    group by v.postid
),
post_with_votes as (
    select
        pe.id as post_id,
        pe.owneruserid as user_id,
        pe.posttypeid,
        pe.creationdate,
        pe.score,
        pe.viewcount,
        pe.title,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.favorites,0) as fav_votes,
        coalesce(va.bounties,0) as bounty_votes,
        coalesce(va.bounty_amount,0) as bounty_amount
    from posts_expanded pe
    left join votes_agg va on va.postid = pe.id
),
recent_activity as (
    select
        p.owneruserid as user_id,
        max(p.lastactivitydate) as last_activity_date,
        count(*) filter (where p.lastactivitydate >= now() - interval '30 days') as activity_30d_posts
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
links_cte as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
dup_network as (
    select
        pwv.user_id,
        count(distinct case when l.is_duplicate = 1 then pwv.post_id end) as dup_posts,
        count(distinct case when l.is_duplicate = 1 then l.relatedpostid end) as dup_targets
    from post_with_votes pwv
    left join links_cte l on l.postid = pwv.post_id
    group by pwv.user_id
),
comments_agg as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        sum(c.score) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
      and c.creationdate >= now() - interval '5 years'
    group by c.userid
),
edits_agg as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        min(ph.creationdate) as first_edit_date,
        max(ph.creationdate) as last_edit_date
    from posthistory ph
    where ph.userid is not null
      and ph.creationdate >= now() - interval '5 years'
    group by ph.userid
),
tag_usage as (
    select
        pe.owneruserid as user_id,
        lower(trim(t)) as tag,
        count(*) as tag_posts,
        sum(pe.score) as tag_score
    from posts_expanded pe
    cross join lateral unnest(pe.tag_array) as t
    where pe.owneruserid is not null
      and pe.posttypeid = 1
    group by pe.owneruserid, lower(trim(t))
),
top_tag_per_user as (
    select distinct on (tu.user_id)
        tu.user_id,
        tu.tag as top_tag,
        tu.tag_posts,
        tu.tag_score
    from tag_usage tu
    order by tu.user_id, tu.tag_posts desc, tu.tag_score desc, tu.tag
),
user_ranks as (
    select
        u.id as user_id,
        rank() over (order by u.reputation desc, u.id) as rank_by_rep,
        rank() over (order by coalesce(upm.total_score,0) desc, u.id) as rank_by_post_score,
        rank() over (order by coalesce(upm.total_views,0) desc, u.id) as rank_by_views
    from users u
    left join user_post_metrics upm on upm.user_id = u.id
),
question_answer_ratio as (
    select
        u.id as user_id,
        case
            when coalesce(upm.answers,0) = 0 and coalesce(upm.questions,0) = 0 then null
            when coalesce(upm.answers,0) = 0 then 0.0
            else coalesce(upm.questions::numeric,0) / nullif(upm.answers::numeric,0)
        end as q_to_a_ratio
    from users u
    left join user_post_metrics upm on upm.user_id = u.id
),
user_last_seen as (
    select
        u.id as user_id,
        greatest(u.lastaccessdate, coalesce(ra.last_activity_date, timestamp 'epoch')) as last_seen
    from users u
    left join recent_activity ra on ra.user_id = u.id
),
active_recent_users as (
    select
        ru.*
    from recent_users ru
    where ru.rn_in_cohort <= 200
),
final_scores as (
    select
        ar.user_id,
        ar.displayname,
        ar.reputation,
        ar.cohort_month,
        coalesce(upm.questions,0) as questions,
        coalesce(upm.answers,0) as answers,
        coalesce(upm.other_posts,0) as other_posts,
        coalesce(upm.total_score,0) as total_post_score,
        coalesce(upm.total_views,0) as total_post_views,
        coalesce(upm.total_comments,0) as total_post_comments,
        coalesce(upm.total_favs,0) as total_post_favs,
        coalesce(va_sum.upvotes,0) as lifetime_upvotes_on_recent_posts,
        coalesce(va_sum.downvotes,0) as lifetime_downvotes_on_recent_posts,
        coalesce(va_sum.favorite_votes,0) as lifetime_favorite_votes_on_recent_posts,
        coalesce(va_sum.bounty_amount,0) as lifetime_bounty_amount_on_recent_posts,
        coalesce(uba.badge_count,0) as badge_count,
        coalesce(uba.gold_badges,0) as gold_badges,
        coalesce(uba.silver_badges,0) as silver_badges,
        coalesce(uba.bronze_badges,0) as bronze_badges,
        uba.first_badge_date,
        uba.last_badge_date,
        coalesce(ca.comments_made,0) as comments_made,
        coalesce(ca.comment_score,0) as comment_score,
        ca.last_comment_date,
        coalesce(ea.edit_events,0) as edit_events,
        coalesce(ea.close_votes_events,0) as close_votes_events,
        coalesce(ea.reopen_events,0) as reopen_events,
        ea.first_edit_date,
        ea.last_edit_date,
        coalesce(dn.dup_posts,0) as duplicate_posts_flagged,
        coalesce(dn.dup_targets,0) as duplicate_targets_linked,
        ttpu.top_tag,
        ttpu.tag_posts as top_tag_posts,
        ttpu.tag_score as top_tag_score,
        ur.rank_by_rep,
        ur.rank_by_post_score,
        ur.rank_by_views,
        qar.q_to_a_ratio,
        uls.last_seen,
        case
            when coalesce(upm.answers,0) + coalesce(upm.questions,0) = 0 then 0
            else round(
                (
                    0.35 * least(coalesce(upm.total_score,0)::numeric, 100000) / 100000 +
                    0.20 * least(coalesce(upm.total_views,0)::numeric, 2000000) / 2000000 +
                    0.15 * least(coalesce(va_sum.upvotes,0)::numeric, 50000) / 50000 -
                    0.05 * least(coalesce(va_sum.downvotes,0)::numeric, 5000) / 5000 +
                    0.10 * least(coalesce(uba.badge_count,0)::numeric, 1000) / 1000 +
                    0.05 * least(coalesce(ca.comment_score,0)::numeric, 20000) / 20000 +
                    0.05 * case when qar.q_to_a_ratio is null then 0.5
                                when qar.q_to_a_ratio between 0.2 and 1.5 then 1
                                else 0.7 end +
                    0.05 * case when ttpu.top_tag is null then 0 else 1 end
                )::numeric, 6
            )
        end as engagement_score
    from active_recent_users ar
    left join user_post_metrics upm on upm.user_id = ar.user_id
    left join (
        select
            pwv.user_id,
            sum(pwv.upvotes) as upvotes,
            sum(pwv.downvotes) as downvotes,
            sum(pwv.fav_votes) as favorite_votes,
            sum(pwv.bounty_amount) as bounty_amount
        from post_with_votes pwv
        group by pwv.user_id
    ) va_sum on va_sum.user_id = ar.user_id
    left join user_badge_agg uba on uba.userid = ar.user_id
    left join comments_agg ca on ca.user_id = ar.user_id
    left join edits_agg ea on ea.user_id = ar.user_id
    left join dup_network dn on dn.user_id = ar.user_id
    left join top_tag_per_user ttpu on ttpu.user_id = ar.user_id
    left join user_ranks ur on ur.user_id = ar.user_id
    left join question_answer_ratio qar on qar.user_id = ar.user_id
    left join user_last_seen uls on uls.user_id = ar.user_id
),
null_safety as (
    select
        fs.*,
        coalesce(displayname, '(unknown)') as safe_displayname,
        coalesce(location, '(unknown)') as safe_location
    from final_scores fs
    left join users u on u.id = fs.user_id
),
cohort_stats as (
    select
        cohort_month,
        percentile_cont(0.5) within group (order by engagement_score) as median_engagement,
        avg(engagement_score) as avg_engagement,
        stddev_pop(engagement_score) as std_engagement,
        count(*) as cohort_size
    from final_scores
    group by cohort_month
),
ranked as (
    select
        ns.*,
        cs.median_engagement,
        cs.avg_engagement,
        cs.std_engagement,
        cs.cohort_size,
        rank() over (order by ns.engagement_score desc, ns.reputation desc, ns.user_id) as rank_global,
        rank() over (partition by ns.cohort_month order by ns.engagement_score desc, ns.reputation desc, ns.user_id) as rank_in_cohort,
        avg(ns.engagement_score) over () as overall_avg_engagement,
        (ns.engagement_score - cs.avg_engagement) / nullif(cs.std_engagement,0) as zscore_cohort
    from null_safety ns
    join cohort_stats cs on cs.cohort_month = ns.cohort_month
),
outliers as (
    select
        r.*,
        case when abs(coalesce(zscore_cohort,0)) >= 2 then true else false end as is_outlier
    from ranked r
),
question_quality as (
    select
        pe.owneruserid as user_id,
        avg(case when pe.posttypeid = 1 then pe.score::numeric end) as avg_question_score,
        avg(case when pe.posttypeid = 2 then pe.score::numeric end) as avg_answer_score,
        count(*) filter (where pe.posttypeid = 1 and pe.score >= 5) as good_questions,
        count(*) filter (where pe.posttypeid = 1 and pe.score <= 0) as bad_questions
    from posts_expanded pe
    where pe.owneruserid is not null
    group by pe.owneruserid
)
select
    o.user_id,
    o.safe_displayname as displayname,
    o.reputation,
    to_char(o.cohort_month, 'YYYY-MM') as cohort_month,
    o.questions,
    o.answers,
    o.other_posts,
    o.total_post_score,
    o.total_post_views,
    o.total_post_comments,
    o.total_post_favs,
    o.lifetime_upvotes_on_recent_posts,
    o.lifetime_downvotes_on_recent_posts,
    o.lifetime_favorite_votes_on_recent_posts,
    o.lifetime_bounty_amount_on_recent_posts,
    o.badge_count,
    o.gold_badges,
    o.silver_badges,
    o.bronze_badges,
    o.first_badge_date,
    o.last_badge_date,
    o.comments_made,
    o.comment_score,
    o.last_comment_date,
    o.edit_events,
    o.close_votes_events,
    o.reopen_events,
    o.first_edit_date,
    o.last_edit_date,
    o.duplicate_posts_flagged,
    o.duplicate_targets_linked,
    coalesce(o.top_tag, '(none)') as top_tag,
    coalesce(o.top_tag_posts, 0) as top_tag_posts,
    coalesce(o.top_tag_score, 0) as top_tag_score,
    o.rank_by_rep,
    o.rank_by_post_score,
    o.rank_by_views,
    o.q_to_a_ratio,
    o.last_seen,
    o.engagement_score,
    o.median_engagement,
    o.avg_engagement,
    o.std_engagement,
    o.cohort_size,
    o.rank_global,
    o.rank_in_cohort,
    o.overall_avg_engagement,
    o.zscore_cohort,
    oq.avg_question_score,
    oq.avg_answer_score,
    oq.good_questions,
    oq.bad_questions,
    case
        when o.engagement_score >= o.avg_engagement + coalesce(o.std_engagement,0) then 'Leader'
        when o.engagement_score >= o.median_engagement then 'Above Median'
        else 'Below Median'
    end as cohort_position,
    case when o.is_outlier then 'Yes' else 'No' end as outlier_flag
from outliers o
left join question_quality oq on oq.user_id = o.user_id
where (o.questions + o.answers + o.other_posts) > 0
order by o.rank_global
limit 500;