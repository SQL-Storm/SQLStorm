with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
        date_trunc('month', u.creationdate) as signup_month,
        row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
question_posts as (
    select p.id, p.owneruserid, p.creationdate, p.score, p.viewcount, p.title, p.tags,
           p.answercount, p.commentcount,
           case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select a.id, a.parentid, a.owneruserid, a.creationdate, a.score
    from posts a
    where a.posttypeid = 2
),
user_activity as (
    select
        ru.user_id,
        ru.displayname,
        ru.location_norm,
        ru.reputation,
        ru.signup_month,
        count(distinct q.id) filter (where q.id is not null) as q_count,
        count(distinct a.id) filter (where a.id is not null) as a_count,
        sum(q.viewcount) as q_views,
        sum(q.score) as q_score,
        sum(a.score) as a_score,
        sum(q.is_closed) as q_closed_count,
        max(greatest(coalesce(q.creationdate, timestamp 'epoch'), coalesce(a.creationdate, timestamp 'epoch'))) as last_post_at
    from recent_users ru
    left join question_posts q on q.owneruserid = ru.user_id
    left join answer_posts a on a.owneruserid = ru.user_id
    group by ru.user_id, ru.displayname, ru.location_norm, ru.reputation, ru.signup_month
),
per_post_metrics as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as q_created,
        q.score as q_score,
        q.viewcount as q_views,
        q.is_closed,
        coalesce(q.answercount, 0) as answercount_snapshot,
        count(a.id) as answer_count_actual,
        max(a.score) as best_answer_score,
        min(a.creationdate) as first_answer_at,
        extract(epoch from (min(a.creationdate) - q.creationdate)) as time_to_first_answer_sec
    from question_posts q
    left join answer_posts a on a.parentid = q.id
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.is_closed, q.answercount
),
comment_sentiment as (
    select
        c.postid,
        count(*) as comment_count,
        sum(c.score) as comment_score_sum,
        avg(c.score) as comment_score_avg,
        count(*) filter (where position('thanks' in lower(c.text)) > 0 or position('thank you' in lower(c.text)) > 0) as polite_count,
        count(*) filter (where position('why' in lower(c.text)) > 0 and c.score <= 0) as challenging_count
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by c.postid
),
post_votes as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 8) as bounty_start,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by v.postid
),
dup_graph as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as master_post_id,
        pl.creationdate as dup_link_created
    from postlinks pl
    where pl.linktypeid = 3
),
closed_reasons as (
    select
        ph.postid,
        max(ph.creationdate) as last_closed_at,
        max(case
              when ph.posthistorytypeid = 10 then
                case
                  when coalesce(nullif(trim(ph.comment), ''), '0') ~ '^[0-9]+$' then ph.comment
                  else null
                end
            end) as last_close_reason_id_raw
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
badge_summary as (
    select
        b.userid,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where case when b.tagbased then 1 else 0 end = 1) as tag_badges
    from badges b
    where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by b.userid
),
tag_explode as (
    select
        q.id as post_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from question_posts q
    where q.tags is not null and length(q.tags) > 2
),
tag_popularity as (
    select
        te.tagname,
        count(distinct te.post_id) as posts_with_tag,
        cast(null as numeric) as pop_sketch
    from tag_explode te
    group by te.tagname
),
rich_questions as (
    select
        ppm.question_id,
        ppm.asker_id,
        ppm.q_created,
        ppm.q_score,
        ppm.q_views,
        ppm.is_closed,
        ppm.answercount_snapshot,
        ppm.answer_count_actual,
        ppm.best_answer_score,
        ppm.first_answer_at,
        ppm.time_to_first_answer_sec,
        coalesce(cs.comment_count, 0) as comment_count,
        coalesce(cs.comment_score_sum, 0) as comment_score_sum,
        coalesce(cs.comment_score_avg, 0) as comment_score_avg,
        coalesce(cs.polite_count, 0) as polite_count,
        coalesce(cs.challenging_count, 0) as challenging_count,
        coalesce(pv.upvotes, 0) as upvotes,
        coalesce(pv.downvotes, 0) as downvotes,
        coalesce(pv.bounty_start, 0) as bounty_starts,
        coalesce(pv.bounty_total, 0) as bounty_total,
        dr.master_post_id,
        cr.last_closed_at,
        case when cr.last_close_reason_id_raw is not null and cr.last_close_reason_id_raw <> '' then cast(cr.last_close_reason_id_raw as integer) else null end as last_close_reason_id
    from per_post_metrics ppm
    left join comment_sentiment cs on cs.postid = ppm.question_id
    left join post_votes pv on pv.postid = ppm.question_id
    left join dup_graph dr on dr.dup_post_id = ppm.question_id
    left join closed_reasons cr on cr.postid = ppm.question_id
),
user_rollup as (
    select
        ua.user_id,
        ua.displayname,
        ua.location_norm,
        ua.reputation,
        ua.signup_month,
        ua.q_count,
        ua.a_count,
        ua.q_views,
        ua.q_score,
        ua.a_score,
        ua.q_closed_count,
        ua.last_post_at,
        coalesce(bs.total_badges,0) as total_badges,
        coalesce(bs.gold_badges,0) as gold_badges,
        coalesce(bs.silver_badges,0) as silver_badges,
        coalesce(bs.bronze_badges,0) as bronze_badges,
        coalesce(bs.tag_badges,0) as tag_badges
    from user_activity ua
    left join badge_summary bs on bs.userid = ua.user_id
),
question_tag_summaries as (
    select
        rq.question_id,
        array_agg(distinct te.tagname order by te.tagname) as tags_array,
        count(distinct te.tagname) as tag_count,
        min(tp.posts_with_tag) as min_tag_popularity,
        max(tp.posts_with_tag) as max_tag_popularity
    from rich_questions rq
    left join tag_explode te on te.post_id = rq.question_id
    left join tag_popularity tp on tp.tagname = te.tagname
    group by rq.question_id
),
ranked_questions as (
    select
        rq.question_id,
        rq.asker_id,
        rq.q_created,
        rq.q_score,
        rq.q_views,
        rq.is_closed,
        rq.answercount_snapshot,
        rq.answer_count_actual,
        rq.best_answer_score,
        rq.first_answer_at,
        rq.time_to_first_answer_sec,
        rq.comment_count,
        rq.comment_score_sum,
        rq.comment_score_avg,
        rq.polite_count,
        rq.challenging_count,
        rq.upvotes,
        rq.downvotes,
        rq.bounty_starts,
        rq.bounty_total,
        rq.master_post_id,
        rq.last_closed_at,
        rq.last_close_reason_id,
        qtd.tags_array,
        qtd.tag_count,
        qtd.min_tag_popularity,
        qtd.max_tag_popularity,
        row_number() over (partition by rq.asker_id order by coalesce(rq.q_score, -1000) desc, rq.q_views desc, rq.question_id) as rn_best_by_user,
        ntile(100) over (order by coalesce(rq.q_views,0) desc) as view_percentile,
        lag(rq.q_score) over (partition by rq.asker_id order by rq.q_created) as prev_q_score_same_user
    from rich_questions rq
    left join question_tag_summaries qtd on qtd.question_id = rq.question_id
),
quality_buckets as (
    select
        rq.question_id,
        case
            when rq.q_score >= 10 and rq.answer_count_actual >= 2 then 'high'
            when rq.q_score between 0 and 9 then 'medium'
            else 'low'
        end as quality_bucket,
        case
            when rq.time_to_first_answer_sec is null then 'no-answers'
            when rq.time_to_first_answer_sec <= 3600 then 'fast'
            when rq.time_to_first_answer_sec <= 86400 then 'day'
            else 'slow'
        end as answer_speed_bucket
    from ranked_questions rq
),
user_quality as (
    select
        rq.asker_id as user_id,
        count(*) filter (where qb.quality_bucket = 'high') as high_qs,
        count(*) filter (where qb.quality_bucket = 'medium') as med_qs,
        count(*) filter (where qb.quality_bucket = 'low') as low_qs,
        count(*) filter (where qb.answer_speed_bucket = 'fast') as fast_ans_qs,
        count(*) filter (where rq.is_closed = 1) as closed_qs
    from ranked_questions rq
    left join quality_buckets qb on qb.question_id = rq.question_id
    group by rq.asker_id
),
location_leaders as (
    select
        ur.location_norm,
        ur.user_id,
        dense_rank() over (partition by ur.location_norm order by ur.reputation desc, ur.user_id) as rep_rank_loc,
        dense_rank() over (partition by ur.location_norm order by (ur.q_score + ur.a_score) desc nulls last) as qa_rank_loc
    from user_rollup ur
)
select
    ur.user_id,
    ur.displayname,
    ur.location_norm,
    ur.reputation,
    ur.signup_month,
    ur.q_count,
    ur.a_count,
    ur.q_views,
    ur.q_score,
    ur.a_score,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.tag_badges,
    uq.high_qs,
    uq.med_qs,
    uq.low_qs,
    uq.fast_ans_qs,
    uq.closed_qs,
    ll.rep_rank_loc,
    ll.qa_rank_loc,
    rq.question_id,
    rq.q_created,
    rq.q_score as question_score,
    rq.q_views as question_views,
    rq.answer_count_actual as answers_count,
    rq.best_answer_score,
    rq.first_answer_at,
    rq.time_to_first_answer_sec,
    rq.upvotes,
    rq.downvotes,
    rq.bounty_total,
    rq.master_post_id as duplicate_of,
    rq.last_closed_at,
    rq.last_close_reason_id,
    rq.tags_array,
    rq.tag_count,
    rq.min_tag_popularity,
    rq.max_tag_popularity,
    rq.view_percentile,
    rq.prev_q_score_same_user,
    case when rq.rn_best_by_user <= 3 then true else false end as is_top3_question_for_user
from user_rollup ur
left join user_quality uq on uq.user_id = ur.user_id
left join location_leaders ll on ll.user_id = ur.user_id and ll.location_norm = ur.location_norm
left join ranked_questions rq on rq.asker_id = ur.user_id
where
    (ur.q_count + ur.a_count) > 0
    and coalesce(rq.q_views, 0) + coalesce(ur.q_views, 0) >= 0
    and (rq.last_close_reason_id is null or rq.last_close_reason_id not in (20))
order by
    ur.reputation desc nulls last,
    rq.view_percentile desc nulls last,
    rq.question_id nulls last
limit 1000;