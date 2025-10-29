with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select
        p.id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.answercount,
        p.commentcount,
        p.closeddate,
        p.lastactivitydate
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        a.id,
        a.parentid,
        a.owneruserid,
        a.creationdate,
        a.score
    from posts a
    where a.posttypeid = 2
),
user_activity as (
    select
        ru.user_id,
        count(distinct qp.id) filter (where qp.id is not null) as questions_asked,
        count(distinct ap.id) filter (where ap.id is not null) as answers_posted,
        count(distinct c.id)  filter (where c.id is not null)  as comments_made,
        sum(qp.score) filter (where qp.id is not null)        as question_score_sum,
        sum(ap.score) filter (where ap.id is not null)        as answer_score_sum
    from recent_users ru
    left join question_posts qp on qp.owneruserid = ru.user_id
    left join answer_posts ap   on ap.owneruserid = ru.user_id
    left join comments c        on c.userid = ru.user_id
    group by ru.user_id
),
tag_explode as (
    select
        qp.id as question_id,
        cast(unnest(string_to_array(substring(qp.tags, 2, greatest(length(qp.tags)-2,0)), '><')) as varchar(35)) as tag
    from question_posts qp
    where qp.tags is not null
),
user_top_tags as (
    select
        qp.owneruserid as user_id,
        te.tag,
        count(*) as tag_q_count,
        row_number() over (partition by qp.owneruserid order by count(*) desc, min(qp.creationdate)) as rn
    from question_posts qp
    join tag_explode te on te.question_id = qp.id
    group by qp.owneruserid, te.tag
),
accepted_answer_latency as (
    select
        q.owneruserid as asker_id,
        q.id as question_id,
        q.creationdate as question_created,
        aa.creationdate as accepted_created,
        extract(epoch from (aa.creationdate - q.creationdate)) as latency_seconds
    from question_posts q
    join posts aa on aa.id = q.acceptedanswerid
),
user_latency_stats as (
    select
        asker_id as user_id,
        count(*) as accepted_count,
        avg(latency_seconds) as avg_accept_latency_sec,
        percentile_cont(0.5) within group (order by latency_seconds) as p50_latency_sec
    from accepted_answer_latency
    group by asker_id
),
vote_aggs as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcvd,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcvd,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_rcvd
    from posts p
    left join votes v on v.postid = p.id
    group by p.owneruserid
),
badge_rollup as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) as total_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
close_events as (
    select
        ph.postid,
        ph.userid as closer_user_id,
        ph.creationdate as closed_at,
        ph.comment as close_reason_id_text
    from posthistory ph
    where ph.posthistorytypeid = 10
),
question_close_info as (
    select
        q.id as question_id,
        q.owneruserid as owner_user_id,
        min(ce.closed_at) as first_closed_at,
        count(*) as close_events_count,
        bool_or(ce.close_reason_id_text in ('101','1')) as has_duplicate_reason
    from question_posts q
    left join close_events ce on ce.postid = q.id
    group by q.id, q.owneruserid
),
postlinks_duplicates as (
    select
        pl.postid as duplicate_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_dup_metrics as (
    select
        q.owneruserid as user_id,
        count(distinct q.id) filter (where qci.close_events_count > 0) as questions_ever_closed,
        count(distinct q.id) filter (where qci.has_duplicate_reason) as questions_closed_as_dupe,
        count(distinct d.duplicate_post_id) as questions_marked_dupe,
        count(distinct d.original_post_id) as distinct_originals_referenced
    from question_posts q
    left join question_close_info qci on qci.question_id = q.id
    left join postlinks_duplicates d on d.duplicate_post_id = q.id
    group by q.owneruserid
),
question_recency_buckets as (
    select
        qp.id as question_id,
        qp.owneruserid as user_id,
        case
            when qp.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') then 'd_0_30'
            when qp.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') then 'd_31_90'
            when qp.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '180 days') then 'd_91_180'
            else 'd_181_plus'
        end as recency_bucket,
        qp.score,
        qp.viewcount
    from question_posts qp
),
question_bucket_aggs as (
    select
        user_id,
        recency_bucket,
        count(*) as q_count,
        avg(score) as avg_score,
        avg(viewcount) as avg_views
    from question_recency_buckets
    group by user_id, recency_bucket
),
question_bucket_pivot as (
    select
        user_id,
        sum(case when recency_bucket = 'd_0_30' then q_count else 0 end) as q_0_30,
        sum(case when recency_bucket = 'd_31_90' then q_count else 0 end) as q_31_90,
        sum(case when recency_bucket = 'd_91_180' then q_count else 0 end) as q_91_180,
        sum(case when recency_bucket = 'd_181_plus' then q_count else 0 end) as q_181_plus,
        avg(case when recency_bucket = 'd_0_30' then avg_score end) as avg_score_0_30,
        avg(case when recency_bucket = 'd_31_90' then avg_score end) as avg_score_31_90,
        avg(case when recency_bucket = 'd_91_180' then avg_score end) as avg_score_91_180,
        avg(case when recency_bucket = 'd_181_plus' then avg_score end) as avg_score_181_plus
    from question_bucket_aggs
    group by user_id
),
comment_sentiment_proxy as (
    select
        c.userid as user_id,
        avg(case
                when position('thanks' in lower(c.text)) > 0 then 0.5
                when position('great' in lower(c.text)) > 0 then 0.4
                when position('helpful' in lower(c.text)) > 0 then 0.3
                when position('bad' in lower(c.text)) > 0 then -0.3
                when position('wrong' in lower(c.text)) > 0 then -0.4
                when position('terrible' in lower(c.text)) > 0 then -0.6
                else 0
            end) as sentiment_score
    from comments c
    group by c.userid
),
user_string_features as (
    select
        u.id as user_id,
        length(coalesce(u.displayname,'')) as len_displayname,
        (case when lower(coalesce(u.websiteurl,'')) like '%github.com%' then 1 else 0 end) as has_github_url,
        (case
            when lower(coalesce(u.location,'')) like '%usa%' or lower(coalesce(u.location,'')) like '%u.s.%' or lower(coalesce(u.location,'')) like '%united states%' or lower(coalesce(u.location,'')) like '%new york%' or lower(coalesce(u.location,'')) like '%california%' then 'US-ish'
            when lower(coalesce(u.location,'')) similar to '%(india|delhi|mumbai|bangalore|hyderabad)%' then 'India-ish'
            when lower(coalesce(u.location,'')) like '%europe%' then 'Europe-ish'
            when coalesce(u.location,'') = '' then 'Unknown'
            else 'Other'
         end) as location_bucket
    from users u
),
windowed_user_rank as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ua.questions_asked,
        ua.answers_posted,
        ua.question_score_sum + ua.answer_score_sum as total_post_score,
        dense_rank() over (order by coalesce(ua.question_score_sum,0) + coalesce(ua.answer_score_sum,0) desc, ru.reputation desc) as rank_by_contrib
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
),
final_scores as (
    select
        ru.user_id,
        ru.displayname,
        coalesce(ua.questions_asked,0) as questions_asked,
        coalesce(ua.answers_posted,0) as answers_posted,
        coalesce(ua.question_score_sum,0) as question_score_sum,
        coalesce(ua.answer_score_sum,0) as answer_score_sum,
        coalesce(v.upvotes_rcvd,0) as upvotes_rcvd,
        coalesce(v.downvotes_rcvd,0) as downvotes_rcvd,
        coalesce(v.favorites_rcvd,0) as favorites_rcvd,
        coalesce(br.total_badges,0) as total_badges,
        coalesce(br.gold_badges,0) as gold_badges,
        coalesce(uls.accepted_count,0) as accepted_count,
        uls.avg_accept_latency_sec,
        qbp.q_0_30,
        qbp.q_31_90,
        qbp.q_91_180,
        qbp.q_181_plus,
        cs.sentiment_score,
        w.rank_by_contrib,
        utf.tag as top_tag,
        udf.questions_ever_closed,
        udf.questions_closed_as_dupe,
        udf.questions_marked_dupe,
        udf.distinct_originals_referenced,
        usf.len_displayname,
        usf.has_github_url,
        usf.location_bucket,
        (
            0.30 * ln(1 + greatest(coalesce(ua.answer_score_sum,0),0)) +
            0.20 * ln(1 + greatest(coalesce(ua.question_score_sum,0),0)) +
            0.15 * ln(1 + coalesce(v.upvotes_rcvd,0)) -
            0.10 * ln(1 + coalesce(v.downvotes_rcvd,0)) +
            0.05 * ln(1 + coalesce(br.total_badges,0)) +
            0.05 * (case when uls.avg_accept_latency_sec is null then 0 else 1 / (1 + coalesce(uls.avg_accept_latency_sec,0)/86400.0) end) +
            0.05 * coalesce(cs.sentiment_score,0) +
            0.10 * (case when coalesce(udf.questions_closed_as_dupe,0) > 0 then 0.2 else 1 end)
        ) as composite_score
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join vote_aggs v on v.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join user_latency_stats uls on uls.user_id = ru.user_id
    left join question_bucket_pivot qbp on qbp.user_id = ru.user_id
    left join comment_sentiment_proxy cs on cs.user_id = ru.user_id
    left join windowed_user_rank w on w.user_id = ru.user_id
    left join user_top_tags utf on utf.user_id = ru.user_id and utf.rn = 1
    left join user_dup_metrics udf on udf.user_id = ru.user_id
    left join user_string_features usf on usf.user_id = ru.user_id
),
thresholds as (
    select
        percentile_cont(0.9) within group (order by composite_score) as p90,
        percentile_cont(0.5) within group (order by composite_score) as p50
    from final_scores
),
ranked as (
    select
        fs.*,
        row_number() over (order by fs.composite_score desc, fs.rank_by_contrib, fs.user_id) as rn_desc,
        row_number() over (order by fs.composite_score asc, fs.user_id) as rn_asc
    from final_scores fs
)
select
    r.user_id,
    coalesce(r.displayname, concat('user#', cast(r.user_id as varchar))) as displayname,
    r.questions_asked,
    r.answers_posted,
    r.question_score_sum,
    r.answer_score_sum,
    r.upvotes_rcvd,
    r.downvotes_rcvd,
    r.favorites_rcvd,
    r.total_badges,
    r.gold_badges,
    r.accepted_count,
    round(coalesce(r.avg_accept_latency_sec,0), 2) as avg_accept_latency_sec,
    coalesce(r.q_0_30,0) as q_0_30,
    coalesce(r.q_31_90,0) as q_31_90,
    coalesce(r.q_91_180,0) as q_91_180,
    coalesce(r.q_181_plus,0) as q_181_plus,
    round(coalesce(r.sentiment_score,0), 3) as comment_sentiment_score,
    r.rank_by_contrib,
    coalesce(r.top_tag, '(none)') as top_tag,
    coalesce(r.questions_ever_closed,0) as questions_ever_closed,
    coalesce(r.questions_closed_as_dupe,0) as questions_closed_as_dupe,
    coalesce(r.questions_marked_dupe,0) as questions_marked_dupe,
    coalesce(r.distinct_originals_referenced,0) as distinct_originals_referenced,
    r.len_displayname,
    r.has_github_url,
    r.location_bucket,
    round(cast(r.composite_score as numeric), 4) as composite_score,
    case
        when r.composite_score >= t.p90 then 'top10%'
        when r.composite_score >= t.p50 then 'mid50%'
        else 'bottom40%'
    end as performance_band,
    coalesce((
        select avg(score) from posts p
        where p.owneruserid = r.user_id
          and p.posttypeid in (1,2)
          and p.creationdate >= (cast('2024-10-01 12:34:56' as timestamp) - interval '30 days')
    ), 0) as recent_avg_post_score_last_30d
from ranked r
cross join thresholds t
where (r.rn_desc <= 200 or r.rn_asc <= 50)
order by r.composite_score desc, r.rank_by_contrib, r.user_id;