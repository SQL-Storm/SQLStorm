-- {"query": "175.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3554} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
           date_trunc('month', u.creationdate) as signup_month,
           row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rn_in_month
    from users u
    where u.creationdate >= (select coalesce(max(p.creationdate), cast('2024-10-01 12:34:56' as timestamp) - interval '10 years') - interval '5 years' from posts p)
),
user_activity as (
    select
        u.id as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
        count(distinct c.id) as comment_count,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_made,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_made,
        min(p.creationdate) as first_post_at,
        max(p.lastactivitydate) as last_post_activity_at
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join badges b on b.userid = u.id
    left join votes v on v.userid = u.id
    group by u.id
),
post_links_enriched as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        lt.name as linktype_name,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
    left join linktypes lt on lt.id = pl.linktypeid
),
question_metrics as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.title,
        q.tags,
        q.creationdate,
        q.score as q_score,
        q.viewcount,
        q.favoritecount,
        q.acceptedanswerid,
        count(a.id) as answers_total,
        sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
        max(a.score) as best_answer_score,
        min(a.creationdate) filter (where a.id is not null) as first_answer_at,
        max(a.creationdate) filter (where a.id is not null) as last_answer_at,
        sum(case when ple.is_duplicate = 1 then 1 else 0 end) as duplicate_marks,
        sum(case when ple.linktypeid = 1 then 1 else 0 end) as linked_marks,
        sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events,
        bool_or(ph.posthistorytypeid = 11) as was_reopened
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    left join post_links_enriched ple on ple.postid = q.id
    left join posthistory ph on ph.postid = q.id and ph.posthistorytypeid in (10,11)
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.title, q.tags, q.creationdate, q.score, q.viewcount, q.favoritecount, q.acceptedanswerid
),
answer_accept_latency as (
    select
        qm.question_id,
        qm.asker_id,
        qm.acceptedanswerid,
        qm.first_answer_at,
        qm.last_answer_at,
        (select a.creationdate from posts a where a.id = qm.acceptedanswerid) as accepted_answer_at,
        extract(epoch from ((select a.creationdate from posts a where a.id = qm.acceptedanswerid) - qm.creationdate)) as accept_latency_sec
    from question_metrics qm
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_metrics q
    where q.tags is not null and q.tags like '<%>'
),
tag_quality as (
    select
        te.tagname,
        count(*) as q_count,
        avg(qm.q_score) as avg_q_score,
        percentile_cont(0.5) within group (order by qm.viewcount) as p50_views,
        sum(qm.duplicate_marks) as duplicates_total,
        sum(case when qm.close_events > 0 then 1 else 0 end) as closed_questions
    from tag_expansion te
    join question_metrics qm on qm.question_id = te.question_id
    group by te.tagname
),
user_quality as (
    select
        u.id as user_id,
        coalesce(avg(case when p.posttypeid = 1 then p.score end), 0) as avg_q_score,
        coalesce(avg(case when p.posttypeid = 2 then p.score end), 0) as avg_a_score,
        coalesce(sum(case when p.posttypeid = 2 then p.score end), 0) as total_a_score,
        count(distinct case when p.posttypeid = 1 then p.id end) as q_authored,
        count(distinct case when p.posttypeid = 2 then p.id end) as a_authored
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_outliers as (
    select
        qm.question_id,
        qm.asker_id,
        qm.viewcount,
        qm.q_score,
        qm.duplicate_marks,
        qm.close_events,
        dense_rank() over (order by qm.viewcount desc nulls last) as dr_view,
        dense_rank() over (order by qm.q_score desc nulls last) as dr_score
    from question_metrics qm
),
activity_grain as (
    select
        u.id as user_id,
        date_trunc('day', coalesce(p.creationdate, c.creationdate, v.creationdate, b.date)) as activity_day,
        count(distinct p.id) filter (where p.id is not null) as posts_day,
        count(distinct c.id) filter (where c.id is not null) as comments_day,
        count(distinct v.id) filter (where v.id is not null) as votes_day,
        count(distinct b.id) filter (where b.id is not null) as badges_day
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    left join votes v on v.userid = u.id
    left join badges b on b.userid = u.id
    group by u.id, date_trunc('day', coalesce(p.creationdate, c.creationdate, v.creationdate, b.date))
),
user_activity_windows as (
    select
        ag.user_id,
        activity_day,
        sum(posts_day) over (partition by user_id order by activity_day rows between 6 preceding and current row) as posts_7d,
        sum(comments_day) over (partition by user_id order by activity_day rows between 6 preceding and current row) as comments_7d,
        sum(votes_day) over (partition by user_id order by activity_day rows between 6 preceding and current row) as votes_7d,
        sum(badges_day) over (partition by user_id order by activity_day rows between 6 preceding and current row) as badges_7d
    from activity_grain ag
),
recent_hot_questions as (
    select
        qm.question_id,
        qm.asker_id,
        qm.title,
        qm.viewcount,
        qm.q_score,
        qm.favoritecount,
        ah.accept_latency_sec,
        case
            when qm.viewcount >= (select percentile_cont(0.95) within group (order by viewcount) from question_metrics) then 1
            when qm.q_score >= (select percentile_cont(0.95) within group (order by q_score) from question_metrics) then 1
            else 0
        end as is_hot
    from question_metrics qm
    left join answer_accept_latency ah on ah.question_id = qm.question_id
    where qm.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
user_dim as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.signup_month,
        ua.q_count,
        ua.a_count,
        ua.total_post_score,
        ua.total_question_views,
        ua.comment_count,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        ua.upvotes_made,
        ua.downvotes_made,
        ua.first_post_at,
        ua.last_post_activity_at,
        uq.avg_q_score,
        uq.avg_a_score,
        uq.total_a_score,
        uq.q_authored,
        uq.a_authored,
        ru.websiteurl_norm,
        ru.location,
        ru.rn_in_month
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
),
question_tag_rollup as (
    select
        q.question_id,
        string_agg(distinct lower(te.tagname), ',' order by lower(te.tagname)) as taglist_norm,
        sum(tq.q_count) as tag_q_count_sum,
        avg(tq.avg_q_score) as tag_avg_qscore
    from tag_expansion te
    join question_metrics q on q.question_id = te.question_id
    left join tag_quality tq on tq.tagname = te.tagname
    group by q.question_id
),
dup_clusters as (
    select
        q.question_id,
        count(distinct case when ple.is_duplicate = 1 then ple.relatedpostid end) as distinct_dups,
        bool_or(ple.is_duplicate = 1) as has_dup_flag
    from question_metrics q
    left join post_links_enriched ple on ple.postid = q.question_id
    group by q.question_id
),
accepted_answer_stats as (
    select
        q.question_id,
        a.owneruserid as answerer_id,
        a.score as accepted_score,
        a.creationdate as accepted_created_at
    from question_metrics q
    left join posts a on a.id = q.acceptedanswerid
),
answerer_dim as (
    select
        aas.question_id,
        ud.user_id as answerer_id,
        ud.displayname as answerer_name,
        ud.reputation as answerer_rep,
        ud.avg_a_score as answerer_avg_a_score
    from accepted_answer_stats aas
    left join user_dim ud on ud.user_id = aas.answerer_id
),
final_scores as (
    select
        q.question_id,
        q.asker_id,
        ud.displayname as asker_name,
        ud.reputation as asker_rep,
        ud.total_post_score,
        ud.gold_badges,
        ud.silver_badges,
        ud.bronze_badges,
        qc.taglist_norm,
        qc.tag_q_count_sum,
        qc.tag_avg_qscore,
        rc.is_hot,
        coalesce(ah.accept_latency_sec, 0) as accept_latency_sec,
        coalesce(dc.distinct_dups, 0) as distinct_dups,
        coalesce(q.q_score, 0) as q_score,
        coalesce(q.viewcount, 0) as views,
        coalesce(q.favoritecount, 0) as favs,
        coalesce(ae.accepted_score, 0) as accepted_score,
        coalesce(ad.answerer_rep, 0) as answerer_rep,
        0.4 * coalesce(q.q_score,0)
        + 0.2 * log(1 + greatest(q.viewcount,0))
        + 0.1 * coalesce(q.favoritecount,0)
        + 0.1 * coalesce(ud.reputation,0) / nullif(ud.reputation + 1000,0)
        + 0.1 * coalesce(ad.answerer_rep,0) / nullif(ad.answerer_rep + 1000,0)
        + 0.05 * case when rc.is_hot = 1 then 1 else 0 end
        - 0.05 * coalesce(dc.distinct_dups,0)
        - 0.05 * case when q.close_events > 0 then 1 else 0 end
        - 0.02 * case when ah.accept_latency_sec > 86400 then 1 else 0 end
        as composite_score
    from question_metrics q
    left join user_dim ud on ud.user_id = q.asker_id
    left join question_tag_rollup qc on qc.question_id = q.question_id
    left join recent_hot_questions rc on rc.question_id = q.question_id
    left join answer_accept_latency ah on ah.question_id = q.question_id
    left join dup_clusters dc on dc.question_id = q.question_id
    left join accepted_answer_stats ae on ae.question_id = q.question_id
    left join answerer_dim ad on ad.question_id = q.question_id
),
ranked as (
    select
        fs.*,
        row_number() over (order by fs.composite_score desc nulls last, fs.views desc, fs.q_score desc, fs.question_id) as rn_global,
        row_number() over (partition by coalesce(split_part(qc.taglist_norm, ',', 1), 'untagged') order by fs.composite_score desc nulls last) as rn_by_primary_tag
    from final_scores fs
    left join question_tag_rollup qc on qc.question_id = fs.question_id
),
user_summary as (
    select
        ud.user_id,
        count(distinct r.question_id) filter (where r.rn_by_primary_tag <= 3) as top3_by_tag_questions,
        avg(fs.composite_score) as avg_composite,
        max(fs.composite_score) as max_composite,
        count(*) as questions_considered
    from ranked r
    join final_scores fs on fs.question_id = r.question_id
    join user_dim ud on ud.user_id = fs.asker_id
    group by ud.user_id
),
mix as (
    select
        'A' as bucket, question_id, composite_score from ranked where rn_global % 3 = 1
    union all
    select
        'B' as bucket, question_id, composite_score from ranked where rn_global % 3 = 2
    union all
    select
        'C' as bucket, question_id, composite_score from ranked where rn_global % 3 = 0
),
bucket_stats as (
    select
        bucket,
        count(*) as cnt,
        avg(composite_score) as avg_score,
        min(composite_score) as min_score,
        max(composite_score) as max_score
    from mix
    group by bucket
)
select
    r.question_id,
    r.rn_global,
    r.rn_by_primary_tag,
    fs.composite_score,
    fs.q_score,
    fs.views,
    fs.favs,
    fs.asker_id,
    fs.asker_name,
    fs.asker_rep,
    fs.gold_badges,
    fs.silver_badges,
    fs.bronze_badges,
    fs.taglist_norm,
    fs.tag_q_count_sum,
    fs.tag_avg_qscore,
    fs.is_hot,
    fs.accept_latency_sec,
    fs.distinct_dups,
    bs.bucket,
    bs.avg_score as bucket_avg_score,
    us.avg_composite as user_avg_composite,
    us.max_composite as user_max_composite,
    us.questions_considered as user_questions_considered
from ranked r
join final_scores fs on fs.question_id = r.question_id
left join mix m on m.question_id = r.question_id
left join bucket_stats bs on bs.bucket = m.bucket
left join user_summary us on us.user_id = fs.asker_id
where r.rn_global <= 500
order by r.rn_global;