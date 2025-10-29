with
-- recent active users with stats
active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_hint,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join badges b on b.userid = u.id
    left join posts p on p.owneruserid = u.id
    where u.reputation >= 100
      and u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '5 year' from users)
    group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, country_hint
),
-- questions with rich metrics
question_metrics as (
    select
        q.id as question_id,
        q.owneruserid as owner_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.tags,
        q.title,
        -- normalize tags to an array
        string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') as tag_arr,
        -- accepted answer indicator
        case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        -- recent edits
        sum(case when ph.posthistorytypeid in (4,5,6) then 1 else 0 end) as edit_events,
        -- close/reopen churn
        sum(case when ph.posthistorytypeid in (10,11) then 1 else 0 end) as close_reopen_events,
        -- comments intensity
        coalesce(sum(c.score),0) as comment_score_sum,
        count(distinct c.id) as comment_count,
        -- last activity: ensure all non-aggregated referenced columns are grouped
        greatest(coalesce(q.lastactivitydate, q.creationdate), max(coalesce(c.creationdate, q.creationdate))) as last_activity
    from posts q
    left join posthistory ph on ph.postid = q.id
    left join comments c on c.postid = q.id
    where q.posttypeid = 1
      and q.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 year' from posts where posttypeid = 1)
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.favoritecount, q.tags, q.title, q.acceptedanswerid, q.lastactivitydate
),
-- answers tied to the above questions
answer_metrics as (
    select
        a.parentid as question_id,
        count(*) as answer_cnt,
        sum(a.score) as answer_score_sum,
        cast(avg(a.score) as numeric(12,4)) as answer_score_avg,
        count(*) filter (where a.creationdate <= q.creationdate + interval '2 day') as answers_in_48h,
        max(a.creationdate) as last_answer_date
    from posts a
    join question_metrics q on q.question_id = a.parentid
    where a.posttypeid = 2
    group by a.parentid, q.creationdate
),
-- vote aggregates per question
vote_metrics as (
    select
        v.postid as question_id,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 5) as favorites_legacy,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total,
        min(v.creationdate) filter (where v.votetypeid in (8,9)) as first_bounty_date
    from votes v
    where exists (select 1 from posts p where p.id = v.postid and p.posttypeid = 1)
    group by v.postid
),
-- tag popularity snapshot
tag_pop as (
    select
        t.tagname,
        t.count as tag_global_count,
        row_number() over (order by t.count desc nulls last) as tag_pop_rank
    from tags t
),
-- expand question tags
question_tagged as (
    select
        q.question_id,
        lower(trim(tag)) as tagname
    from question_metrics q
         left join lateral unnest(q.tag_arr) as tag(tag) on true
),
-- link and duplicate information
linkage as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        max(pl.creationdate) as last_link_date,
        bool_or(pl.linktypeid = 3) as has_duplicate_flag
    from postlinks pl
    group by pl.postid
),
-- per-user rolling activity window over questions
user_question_activity as (
    select
        q.owner_id as user_id,
        q.question_id,
        q.creationdate,
        count(*) over (partition by q.owner_id order by q.creationdate rows between 6 preceding and current row) as questions_in_last_7,
        sum(q.score) over (partition by q.owner_id order by q.creationdate rows between 6 preceding and current row) as score_in_last_7
    from question_metrics q
),
-- find anomalous edit bursts using z-score
edit_bursts as (
    select
        q.owner_id,
        q.question_id,
        q.edit_events,
        avg(q.edit_events) over (partition by q.owner_id) as avg_edits_user,
        stddev_samp(q.edit_events) over (partition by q.owner_id) as sd_edits_user,
        case
            when stddev_samp(q.edit_events) over (partition by q.owner_id) is null or stddev_samp(q.edit_events) over (partition by q.owner_id) = 0 then 0
            else (q.edit_events - avg(q.edit_events) over (partition by q.owner_id)) / nullif(stddev_samp(q.edit_events) over (partition by q.owner_id),0)
        end as edit_z
    from question_metrics q
),
-- compute weighted quality score with mixed signals and null logic
quality as (
    select
        q.question_id,
        q.owner_id,
        coalesce(q.score, 0) * 2
        + coalesce(vm.upvotes, 0) * 1.5
        - coalesce(vm.downvotes, 0) * 2
        + coalesce(am.answer_score_sum, 0) * 0.5
        + case when q.has_accepted = 1 then 5 else 0 end
        + least(coalesce(q.viewcount,0)/1000.0, 10)
        + coalesce(cast(q.comment_score_sum as numeric),0) * 0.2
        - coalesce(q.close_reopen_events,0) * 3
        - case when coalesce(lk.has_duplicate_flag,false) then 8 else 0 end
        + coalesce(vm.bounty_total,0) * 0.01
        + coalesce(am.answers_in_48h,0) * 0.7
        as quality_score,
        q.creationdate,
        q.last_activity,
        q.title,
        q.tags
    from question_metrics q
    left join answer_metrics am on am.question_id = q.question_id
    left join vote_metrics vm on vm.question_id = q.question_id
    left join linkage lk on lk.question_id = q.question_id
),
-- correlate questions with tag popularity
quality_with_tags as (
    select
        qu.question_id,
        qu.owner_id,
        qu.quality_score,
        qu.creationdate,
        qu.last_activity,
        qu.title,
        coalesce(qt.tagname, '(no-tag)') as tagname,
        tp.tag_global_count,
        tp.tag_pop_rank
    from quality qu
    left join question_tagged qt on qt.question_id = qu.question_id
    left join tag_pop tp on tp.tagname = qt.tagname
),
-- per-user percentiles of quality
user_quality_rank as (
    select
        owner_id as user_id,
        question_id,
        quality_score,
        ntile(100) over (partition by owner_id order by quality_score desc nulls last) as user_quality_percentile
    from quality
),
-- aggregate per user across tags
user_tag_summary as (
    select
        qwt.owner_id as user_id,
        qwt.tagname,
        count(*) as questions_in_tag,
        cast(avg(qwt.quality_score) as numeric(12,4)) as avg_quality_in_tag,
        min(qwt.quality_score) as min_quality_in_tag,
        max(qwt.quality_score) as max_quality_in_tag,
        avg(coalesce(qwt.tag_global_count,0)) as avg_tag_global_count
    from quality_with_tags qwt
    group by qwt.owner_id, qwt.tagname
),
-- detect users with mixed performance (strong and weak posts)
user_mixed_perf as (
    select
        q.owner_id as user_id,
        count(*) filter (where q.quality_score >= (
            select percentile_disc(0.9) within group (order by quality_score)
            from quality qi where qi.owner_id = q.owner_id
        )) as top_decile_posts,
        count(*) filter (where q.quality_score <= (
            select percentile_disc(0.1) within group (order by quality_score)
            from quality qi where qi.owner_id = q.owner_id
        )) as bottom_decile_posts
    from quality q
    group by q.owner_id
),
-- combine everything to user level
user_rollup as (
    select
        au.user_id,
        au.displayname,
        au.reputation,
        au.country_hint,
        au.gold_badges,
        au.silver_badges,
        au.bronze_badges,
        au.total_posts,
        coalesce(sum(case when q.quality_score is null then 0 else 1 end),0) as questions_considered,
        cast(coalesce(avg(q.quality_score),0) as numeric(12,4)) as avg_quality_all,
        cast(coalesce(avg(case when q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 day' then q.quality_score end),0) as numeric(12,4)) as avg_quality_90d,
        coalesce(max(q.last_activity), au.last_post_activity) as last_activity_any,
        coalesce(sum(case when uq.user_quality_percentile >= 95 then 1 else 0 end),0) as elite_questions,
        coalesce(sum(case when uq.user_quality_percentile <= 5 then 1 else 0 end),0) as poor_questions,
        max(uka.questions_in_last_7) as rolling_7_q_count_max
    from active_users au
    left join quality q on q.owner_id = au.user_id
    left join user_quality_rank uq on uq.question_id = q.question_id
    left join user_question_activity uka on uka.user_id = au.user_id
    group by au.user_id, au.displayname, au.reputation, au.country_hint, au.gold_badges, au.silver_badges, au.bronze_badges, au.total_posts, au.last_post_activity
),
-- pick each user's dominant tag by quality-weighted presence
user_dominant_tag as (
    select distinct on (uts.user_id)
        uts.user_id,
        uts.tagname,
        uts.questions_in_tag,
        uts.avg_quality_in_tag
    from user_tag_summary uts
    order by uts.user_id, uts.avg_quality_in_tag desc nulls last, uts.questions_in_tag desc
),
-- final scoring with penalties/bonuses
user_final as (
    select
        ur.user_id,
        ur.displayname,
        ur.reputation,
        ur.country_hint,
        ur.gold_badges, ur.silver_badges, ur.bronze_badges,
        ur.total_posts,
        ur.questions_considered,
        ur.avg_quality_all,
        ur.avg_quality_90d,
        ur.elite_questions,
        ur.poor_questions,
        udt.tagname as dominant_tag,
        coalesce(udt.avg_quality_in_tag,0) as dominant_tag_quality,
        -- dynamic score mixing recent performance and badges
        (ur.avg_quality_90d * 0.6 + ur.avg_quality_all * 0.4)
        + (least(ur.gold_badges,10) * 2 + least(ur.silver_badges,20) * 0.5 + least(ur.bronze_badges,30) * 0.2)
        + case when ur.elite_questions >= 3 then 5 else 0 end
        - case when ur.poor_questions >= 3 then 4 else 0 end
        + case when coalesce(udt.avg_quality_in_tag,0) > ur.avg_quality_all then 2 else 0 end
        - case when ur.questions_considered < 5 then 3 else 0 end
        as user_performance_score
    from user_rollup ur
    left join user_dominant_tag udt on udt.user_id = ur.user_id
),
-- derive global rank using multiple tie-breakers
global_ranked as (
    select
        uf.*,
        row_number() over (
            order by uf.user_performance_score desc nulls last,
                     uf.avg_quality_90d desc nulls last,
                     uf.elite_questions desc,
                     uf.reputation desc,
                     uf.questions_considered desc
        ) as global_rank
    from user_final uf
)
-- final output with sample of top and bottom via set operations and complex predicates
select *
from (
    select gr.*
    from global_ranked gr
    where gr.global_rank <= 50
    union all
    select gr.*
    from global_ranked gr
    where gr.global_rank > (select greatest(max(global_rank) - 49, 0) from global_ranked)
) s
where (s.country_hint is not null or s.reputation > 1000)
  and not (s.dominant_tag is null and s.questions_considered >= 10)
order by s.global_rank, s.user_id;