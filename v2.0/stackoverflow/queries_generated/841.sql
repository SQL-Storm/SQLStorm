-- {"query": "841.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3175} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        u.upvotes,
        u.downvotes,
        u.views,
        coalesce(nullif(trim(u.location), ''), 'UNKNOWN') as norm_location,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
user_posts as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.communityowneddate,
        p.tags,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer
    from posts p
    where p.owneruserid is not null
),
agg_votes as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
    from votes v
    group by v.postid
),
tag_expanded as (
    select
        up.user_id,
        up.post_id,
        unnest(string_to_array(substring(up.tags, 2, length(up.tags)-2), '><')) as tag
    from user_posts up
    where up.tags is not null
),
tag_quality as (
    select
        te.tag,
        count(distinct te.post_id) as posts_with_tag,
        avg(p.score)::numeric(12,4) as avg_score_for_tag,
        percentile_cont(0.9) within group (order by p.score) as p90_score_for_tag
    from tag_expanded te
    join posts p on p.id = te.post_id
    group by te.tag
),
closed_reasons as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as close_reason_id,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as close_date
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_id,
        count(*) as dup_link_count,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(coalesce(c.score,0))::numeric(12,4) as avg_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.userid is not null
    group by c.userid
),
post_enriched as (
    select
        up.*,
        av.upvotes,
        av.downvotes,
        av.bounty_started,
        av.bounty_awarded,
        av.favorites,
        cr.close_reason_id,
        cr.close_date,
        dl.dup_link_count,
        dl.first_link_date,
        case
            when up.closeddate is not null then 1
            when cr.close_reason_id is not null then 1
            else 0
        end as was_closed_flag,
        case when dl.dup_link_count is not null then 1 else 0 end as is_duplicate_flag
    from user_posts up
    left join agg_votes av on av.postid = up.post_id
    left join closed_reasons cr on cr.postid = up.post_id
    left join dup_links dl on dl.dup_post_id = up.post_id
),
user_activity as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.norm_location,
        coalesce(sum(pe.is_question),0) as questions,
        coalesce(sum(pe.is_answer),0) as answers,
        coalesce(sum(case when pe.was_closed_flag = 1 then 1 else 0 end),0) as closed_posts,
        coalesce(sum(case when pe.is_duplicate_flag = 1 then 1 else 0 end),0) as duplicate_posts,
        coalesce(sum(pe.score),0) as total_post_score,
        coalesce(sum(coalesce(pe.upvotes,0)),0) as total_upvotes,
        coalesce(sum(coalesce(pe.downvotes,0)),0) as total_downvotes,
        coalesce(sum(coalesce(pe.favorites,0)),0) as total_favorites,
        coalesce(sum(coalesce(pe.viewcount,0)),0) as total_views,
        max(pe.creationdate) as last_post_at
    from recent_users ru
    left join post_enriched pe on pe.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.cohort_month, ru.norm_location
),
location_rollup as (
    select
        ua.norm_location,
        count(*) as users_in_loc,
        avg(ua.reputation)::numeric(12,2) as avg_rep_loc,
        percentile_cont(0.5) within group (order by ua.reputation) as median_rep_loc
    from user_activity ua
    group by ua.norm_location
),
cohort_rollup as (
    select
        ua.cohort_month,
        count(*) as users_in_cohort,
        avg(ua.total_post_score)::numeric(12,2) as avg_score_cohort,
        avg(ua.questions + ua.answers)::numeric(12,2) as avg_posts_cohort
    from user_activity ua
    group by ua.cohort_month
),
quality_scoring as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.cohort_month,
        ua.norm_location,
        ua.questions,
        ua.answers,
        ua.closed_posts,
        ua.duplicate_posts,
        ua.total_post_score,
        ua.total_upvotes,
        ua.total_downvotes,
        ua.total_favorites,
        ua.total_views,
        ua.last_post_at,
        lr.users_in_loc,
        cr.users_in_cohort,
        case
            when (ua.total_upvotes + ua.total_downvotes) = 0 then null
            else (ua.total_upvotes::numeric / nullif(ua.total_upvotes + ua.total_downvotes,0))
        end as upvote_ratio,
        case when ua.answers = 0 then null else ua.total_post_score::numeric / ua.answers end as score_per_answer,
        case when ua.questions = 0 then null else ua.total_favorites::numeric / ua.questions end as favorites_per_question,
        rank() over (order by ua.total_post_score desc, ua.total_upvotes desc) as rnk_score,
        dense_rank() over (partition by ua.norm_location order by ua.total_post_score desc) as rnk_loc,
        row_number() over (partition by ua.cohort_month order by ua.total_upvotes desc) as rn_cohort
    from user_activity ua
    left join location_rollup lr on lr.norm_location = ua.norm_location
    left join cohort_rollup cr on cr.cohort_month = ua.cohort_month
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) filter (
            where exists (
                select 1
                from posts q
                where q.id = a.parentid
                  and q.acceptedanswerid = a.id
            )
        ) as accepted_answers,
        count(*) as total_answers
    from posts a
    where a.posttypeid = 2 and a.owneruserid is not null
    group by a.owneruserid
),
string_patterns as (
    select
        u.id as user_id,
        sum(case when lower(coalesce(u.websiteurl,'')) like '%github.%' then 1 else 0 end) as has_github,
        sum(case when lower(coalesce(u.location,'')) similar to '%(us|united states|ca|canada|uk|united kingdom)%' then 1 else 0 end) as is_na_or_uk
    from users u
    group by u.id
),
final_scores as (
    select
        qs.*,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(aa.total_answers,0) as total_answers_count,
        case
            when coalesce(aa.total_answers,0) = 0 then null
            else aa.accepted_answers::numeric / nullif(aa.total_answers,0)
        end as accept_rate,
        sp.has_github,
        sp.is_na_or_uk,
        -- composite score mixing several aspects with arbitrary weights
        (
            0.40 * coalesce(qs.total_post_score,0) +
            0.25 * coalesce(qs.total_upvotes - qs.total_downvotes,0) +
            0.10 * coalesce(qs.total_favorites,0) +
            0.10 * coalesce(qs.total_views,0) / 1000.0 +
            0.10 * coalesce((qs.upvote_ratio * 100.0), 0) +
            0.05 * coalesce((case when qs.closed_posts = 0 then 10 else 0 end), 0)
        )::numeric(18,4) as composite_score
    from quality_scoring qs
    left join answer_accepts aa on aa.user_id = qs.user_id
    left join string_patterns sp on sp.user_id = qs.user_id
),
posttype_labels as (
    select id, name from posttypes
),
vote_labels as (
    select id, name from votetypes
),
cross_checks as (
    select
        p.owneruserid as user_id,
        max(case when p.posttypeid = 1 then 1 else 0 end) as has_any_question,
        max(case when p.posttypeid = 2 then 1 else 0 end) as has_any_answer
    from posts p
    group by p.owneruserid
),
null_safety as (
    select
        fs.*,
        case when cc.user_id is null then 1 else 0 end as user_missing_in_posts
    from final_scores fs
    left join cross_checks cc on cc.user_id = fs.user_id
),
ranked as (
    select
        ns.*,
        percent_rank() over (order by composite_score) as pr_all,
        cume_dist() over (order by composite_score desc) as cd_desc,
        ntile(10) over (order by composite_score desc) as decile_desc,
        sum(case when composite_score is not null then 1 else 0 end) over () as total_scored_users
    from null_safety ns
)
select
    r.user_id,
    r.displayname,
    r.reputation,
    r.cohort_month,
    r.norm_location,
    r.questions,
    r.answers,
    r.closed_posts,
    r.duplicate_posts,
    r.total_post_score,
    r.total_upvotes,
    r.total_downvotes,
    r.total_favorites,
    r.total_views,
    r.accept_rate,
    r.upvote_ratio,
    r.score_per_answer,
    r.favorites_per_question,
    r.has_github,
    r.is_na_or_uk,
    r.composite_score,
    r.rnk_score,
    r.rnk_loc,
    r.rn_cohort,
    r.pr_all,
    r.cd_desc,
    r.decile_desc,
    r.total_scored_users,
    -- correlated subquery example: last three tag names used by the user by recency
    (
        select string_agg(tg.tag, ', ' order by tg_seq.rn)
        from (
            select te.tag, row_number() over (partition by te.user_id order by p.creationdate desc) as rn
            from tag_expanded te
            join posts p on p.id = te.post_id
            where te.user_id = r.user_id
        ) tg_seq
        join lateral (
            select tag from (values (tg_seq.tag)) as v(tag)
        ) tg on true
        where tg_seq.rn <= 3
    ) as recent_tags,
    -- set operator example: count of unique duplicate targets intersecting with user’s own posts
    (
        select count(*) from (
            select distinct dl.relatedpostid
            from postlinks dl
            join posts p1 on p1.id = dl.postid
            where dl.linktypeid = 3 and p1.owneruserid = r.user_id
            intersect
            select distinct p2.id
            from posts p2
            where p2.owneruserid = r.user_id
        ) s
    ) as self_dup_intersections,
    -- null logic heavy expression
    case
        when r.user_missing_in_posts = 1 then 'NO_POSTS'
        when r.answers = 0 and r.questions = 0 then 'INACTIVE'
        when r.answers > r.questions then 'ANSWERER'
        when r.questions > r.answers then 'QUESTIONER'
        else 'BALANCED'
    end as activity_profile
from ranked r
where
    (r.composite_score is not null and r.decile_desc <= 3)
    or (r.accept_rate is not null and r.accept_rate >= 0.5)
order by
    r.decile_desc asc,
    r.composite_score desc nulls last,
    r.rnk_score asc
limit 250;