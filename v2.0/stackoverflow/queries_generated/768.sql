-- {"query": "768.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3421} 
with
-- Identify active users with diverse activity across posts, comments, votes, badges
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        coalesce(u.location, 'Unknown') as location,
        date_trunc('month', u.creationdate) as user_cohort_month,
        count(distinct p.id) filter (where p.owneruserid = u.id) as posts_authored,
        count(distinct c.id) filter (where c.userid = u.id) as comments_made,
        count(distinct v.id) filter (where v.userid = u.id) as votes_cast,
        count(distinct b.id) as badges_earned,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(least(coalesce(p.score,0), 0)) as worst_post_score,
        max(coalesce(p.score,0)) as best_post_score
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join votes v on v.userid = u.id
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location
),
-- Pull question and answer aggregates with window functions
post_metrics as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.parentid,
        p.acceptedanswerid,
        p.tags,
        p.title,
        -- tag count using string operations
        case
            when p.posttypeid = 1 and p.tags is not null
            then cardinality(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))
            else 0
        end as tag_count,
        -- rolling rank by score within month/type
        rank() over (partition by p.posttypeid, date_trunc('month', p.creationdate) order by p.score desc nulls last) as score_rank_in_month,
        -- percentile of score within all posts of same type
        percent_rank() over (partition by p.posttypeid order by p.score) as score_percentile_in_type,
        -- views per day since creation (avoid divide-by-zero)
        p.viewcount / greatest(extract(epoch from (coalesce(p.lastactivitydate, now()) - p.creationdate)) / 86400.0, 1) as views_per_day
    from posts p
    where p.creationdate is not null
),
-- Votes by type per post and net score verification
vote_agg as (
    select
        v.postid,
        count(*) filter (where vt.name = 'UpMod') as upvotes,
        count(*) filter (where vt.name = 'DownMod') as downvotes,
        count(*) filter (where vt.name = 'Favorite') as favorites,
        count(*) filter (where vt.name in ('BountyStart','BountyClose')) as bounty_events,
        sum(coalesce(v.bountyamount,0)) as bounty_amount_total,
        min(v.creationdate) as first_vote_at,
        max(v.creationdate) as last_vote_at
    from votes v
    join votetypes vt on vt.id = v.votetypeid
    group by v.postid
),
-- Comments signal and last comment author per post
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
        max(c.creationdate) as last_comment_at,
        max(c.userid) filter (where c.creationdate = (select max(c2.creationdate) from comments c2 where c2.postid = c.postid)) as last_comment_userid
    from comments c
    group by c.postid
),
-- Closing and migration history per post (uses complicated JSON/text, but summarized)
history_agg as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        count(*) filter (where ph.posthistorytypeid in (35,36)) as migration_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_close_at
    from posthistory ph
    group by ph.postid
),
-- Link graph: duplicates and linked posts
link_agg as (
    select
        pl.postid,
        count(*) filter (where lt.name = 'Duplicate') as duplicate_links,
        count(*) filter (where lt.name = 'Linked') as linked_links,
        -- count distinct related questions
        count(distinct pl.relatedpostid) as related_distinct
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    group by pl.postid
),
-- Tag popularity snapshot to join by extracted tag names
tag_popularity as (
    select
        t.tagname,
        t.count as tag_count_total,
        row_number() over (order by t.count desc, t.tagname asc) as tag_pop_rank
    from tags t
),
-- Explode tags from questions
question_tags as (
    select
        pm.id as post_id,
        unnest(string_to_array(substring(pm.tags, 2, length(pm.tags)-2), '><')) as tagname
    from post_metrics pm
    where pm.posttypeid = 1 and pm.tags is not null and length(pm.tags) > 2
),
-- Aggregate per-question tag popularity signals
question_tag_agg as (
    select
        qt.post_id,
        count(*) as tag_used_count,
        avg(tp.tag_count_total::numeric) as avg_tag_popularity,
        min(tp.tag_pop_rank) as best_tag_rank
    from question_tags qt
    left join tag_popularity tp on lower(tp.tagname) = lower(qt.tagname)
    group by qt.post_id
),
-- Derive accepted answer performance
accepted_answer_metrics as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.score as answer_score,
        a.creationdate as answer_created,
        q.creationdate as question_created,
        extract(epoch from (a.creationdate - q.creationdate))/3600.0 as hours_to_accept,
        -- answers competing count
        count(*) filter (where a2.parentid = q.id) over (partition by q.id) as total_answers_for_q
    from posts q
    join posts a on a.id = q.acceptedanswerid
    left join posts a2 on a2.parentid = q.id
    where q.posttypeid = 1 and q.acceptedanswerid is not null
),
-- Build a monthly performance cohort for questions
question_monthly as (
    select
        date_trunc('month', pm.creationdate) as month,
        pm.owneruserid,
        count(*) filter (where pm.posttypeid = 1) as questions,
        avg(pm.score) filter (where pm.posttypeid = 1) as avg_q_score,
        avg(pm.viewcount) filter (where pm.posttypeid = 1) as avg_q_views,
        sum(case when pm.posttypeid = 1 and pm.answercount >= 1 then 1 else 0 end) as q_with_answers
    from post_metrics pm
    group by date_trunc('month', pm.creationdate), pm.owneruserid
),
-- Compute composite quality index per post combining several signals
post_quality as (
    select
        pm.id as post_id,
        pm.posttypeid,
        pm.owneruserid,
        pm.score,
        pm.viewcount,
        coalesce(va.upvotes - va.downvotes, 0) as vote_delta,
        coalesce(va.favorites, 0) as favorites,
        coalesce(ca.comment_count, 0) as comments,
        pm.views_per_day,
        pm.score_percentile_in_type,
        pm.score_rank_in_month,
        coalesce(la.duplicate_links, 0) as duplicate_links,
        coalesce(la.linked_links, 0) as linked_links,
        coalesce(ha.close_events, 0) as close_events,
        -- composite index with weighted components
        (
            coalesce(pm.score,0) * 1.0
            + coalesce(va.upvotes,0) * 0.5
            - coalesce(va.downvotes,0) * 0.7
            + coalesce(va.favorites,0) * 0.8
            + coalesce(pm.viewcount,0) * 0.01
            - coalesce(ha.close_events,0) * 2.5
            - coalesce(la.duplicate_links,0) * 1.2
            + coalesce(linked_links,0) * 0.3
            - coalesce(ca.positive_comments,0) * 0.2
        ) as quality_index
    from post_metrics pm
    left join vote_agg va on va.postid = pm.id
    left join comment_agg ca on ca.postid = pm.id
    left join link_agg la on la.postid = pm.id
    left join history_agg ha on ha.postid = pm.id
),
-- Combine everything for questions only
question_facts as (
    select
        pm.id as question_id,
        pm.owneruserid as asker_id,
        pm.creationdate as asked_at,
        pm.score as q_score,
        pm.viewcount as q_views,
        pm.answercount,
        pm.tag_count,
        pm.score_rank_in_month,
        pm.score_percentile_in_type,
        qta.avg_tag_popularity,
        qta.best_tag_rank,
        aa.hours_to_accept,
        aa.total_answers_for_q,
        pq.quality_index as q_quality_index
    from post_metrics pm
    left join question_tag_agg qta on qta.post_id = pm.id
    left join accepted_answer_metrics aa on aa.question_id = pm.id
    left join post_quality pq on pq.post_id = pm.id
    where pm.posttypeid = 1
),
-- Build per-user rolling metrics windowed over time
user_time_windows as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.location,
        ua.user_cohort_month,
        sum(qa.q_score) over (partition by ua.user_id order by qa.asked_at rows between unbounded preceding and current row) as cum_q_score,
        avg(qa.q_quality_index) over (partition by ua.user_id order by qa.asked_at rows between 10 preceding and current row) as rolling_q_quality_avg_11,
        count(*) over (partition by ua.user_id) as total_questions_by_user
    from user_activity ua
    join question_facts qa on qa.asker_id = ua.user_id
),
-- Outlier detection flags using correlated subqueries and null-safe logic
post_outliers as (
    select
        pq.post_id,
        pq.owneruserid as user_id,
        pq.quality_index,
        pq.score,
        pq.viewcount,
        case
            when pq.quality_index > (
                select coalesce(avg(pq2.quality_index) + 2*stddev_pop(pq2.quality_index), 999999)
                from post_quality pq2
                where pq2.posttypeid = pq.posttypeid
            ) then 'High'
            when pq.quality_index < (
                select coalesce(avg(pq2.quality_index) - 2*stddev_pop(pq2.quality_index), -999999)
                from post_quality pq2
                where pq2.posttypeid = pq.posttypeid
            ) then 'Low'
            else 'Normal'
        end as outlier_band
    from post_quality pq
)
select
    -- final selection mixing everything with diverse constructs
    u.id as user_id,
    coalesce(nullif(trim(u.displayname), ''), concat('user#', u.id::text)) as user_handle,
    u.reputation,
    utw.user_cohort_month,
    ua.posts_authored,
    ua.comments_made,
    ua.votes_cast,
    ua.badges_earned,
    ua.gold_badges || '/' || ua.silver_badges || '/' || ua.bronze_badges as badge_mix,
    -- Window function across final result set
    dense_rank() over (order by coalesce(utw.rolling_q_quality_avg_11, 0) desc nulls last) as quality_rank_global,
    sum(case when po.outlier_band = 'High' then 1 else 0 end) over (partition by u.id) as high_outlier_posts,
    sum(case when po.outlier_band = 'Low' then 1 else 0 end) over (partition by u.id) as low_outlier_posts,
    round(coalesce(utw.rolling_q_quality_avg_11, 0)::numeric, 2) as rolling_q_quality_avg_11,
    round(coalesce(avg(qf.q_quality_index) over (partition by u.id), 0)::numeric, 2) as avg_q_quality_overall,
    count(distinct qf.question_id) as questions_sampled,
    -- set operator via aggregate of distinct months (emulate string agg for variety)
    string_agg(distinct to_char(date_trunc('month', qf.asked_at), 'YYYY-MM'), ',' order by to_char(date_trunc('month', qf.asked_at), 'YYYY-MM')) as active_months,
    -- elaborate predicate-driven KPIs
    avg(case when qf.tag_count >= 3 and coalesce(qf.avg_tag_popularity,0) > 0 then qf.q_score else null end) as avg_score_multi_tag,
    avg(case when qf.hours_to_accept between 0 and 48 then qf.q_score else null end) as avg_score_fast_accept,
    sum(case when qf.best_tag_rank is not null and qf.best_tag_rank <= 100 then 1 else 0 end) as questions_with_top100_tag,
    max(qf.score_rank_in_month) as worst_rank_in_month,
    min(qf.score_rank_in_month) as best_rank_in_month
from users u
left join user_activity ua on ua.user_id = u.id
left join user_time_windows utw on utw.user_id = u.id
left join question_facts qf on qf.asker_id = u.id
left join post_outliers po on po.user_id = u.id
where
    -- complicated predicate including null logic and string ops
    coalesce(u.reputation, 0) >= 100
    and (u.websiteurl is null or position('stack' in lower(u.websiteurl)) > 0 or length(u.websiteurl) < 15)
    and (
        ua.posts_authored is not null
        or exists (
            select 1
            from posts p_sub
            where p_sub.owneruserid = u.id
              and p_sub.posttypeid in (1,2)
              and coalesce(p_sub.score,0) >= 0
        )
    )
group by
    u.id, u.displayname, u.reputation, utw.user_cohort_month, ua.posts_authored, ua.comments_made, ua.votes_cast, ua.badges_earned, ua.gold_badges, ua.silver_badges, ua.bronze_badges, utw.rolling_q_quality_avg_11
order by
    quality_rank_global nulls last,
    avg_q_quality_overall desc nulls last,
    questions_sampled desc
limit 200;