-- {"query": "304.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2930} 
with
-- Active users with engagement metrics
user_engagement as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_guess,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers,
        sum(coalesce(p.score, 0)) as post_score,
        sum(coalesce(p.viewcount, 0)) as views,
        sum(coalesce(p.commentcount, 0)) as comments_on_posts,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as received_upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as received_downvotes,
        count(distinct b.id) as badges_count,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    left join votes v on v.postid = p.id
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate, country_guess
),
-- Tag popularity and recency
tag_recency as (
    select
        t.tagname,
        t.count as total_tag_count,
        max(p.creationdate) as last_tagged_date,
        avg(p.score) filter (where p.posttypeid = 1) as avg_question_score,
        avg(p.score) filter (where p.posttypeid = 2) as avg_answer_score
    from tags t
    left join posts p
      on p.posttypeid in (1,2)
     and p.tags is not null
     and ('<' || t.tagname || '>') = any (string_to_array(substring(p.tags, 2, length(p.tags)-2), '><'))
    group by t.tagname, t.count
),
-- Per-question metrics including duplicate/links, favorites, and close reasons
question_metrics as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_date,
        q.title,
        q.viewcount,
        q.score as q_score,
        q.answercount,
        exists (
            select 1
            from posts a
            where a.parentid = q.id
              and a.score > 0
        ) as has_positive_answer,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        count(pl_dup.id) as duplicate_marks,
        count(pl_link.id) as linked_relations,
        max(ph_close.creationdate) as last_closed_date,
        max(case when ph_close.posthistorytypeid = 11 then ph_close.creationdate end) as reopened_date,
        max(
          case
            when ph_close.posthistorytypeid = 10
                 and ph_close.comment ~ '^[0-9]+$' then cast(ph_close.comment as int)
          end
        ) as close_reason_id
    from posts q
    left join votes v on v.postid = q.id
    left join postlinks pl_dup
      on pl_dup.postid = q.id
     and pl_dup.linktypeid = 3
    left join postlinks pl_link
      on pl_link.postid = q.id
     and pl_link.linktypeid = 1
    left join posthistory ph_close
      on ph_close.postid = q.id
     and ph_close.posthistorytypeid in (10,11)
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.title, q.viewcount, q.score, q.answercount
),
-- Expand tags for questions
question_tags as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
),
-- Rolling activity per user with window functions
user_activity_window as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        sum(1) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as running_post_count,
        sum(p.score) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as running_score,
        avg(p.score) over (partition by p.owneruserid order by p.creationdate rows between 10 preceding and current row) as trailing_10_avg_score
    from posts p
    where p.owneruserid is not null
),
-- Correlated subquery to compute median answer score per question
answer_medians as (
    select q.id as question_id,
           percentile_cont(0.5) within group (order by a.score) as median_answer_score
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id
),
-- Recent comment buzz per question
question_comment_buzz as (
    select
        c.postid as question_id,
        count(*) filter (where c.creationdate >= now() - interval '30 days') as comments_30d,
        sum(case when c.score > 0 then 1 else 0 end) as helpful_comments,
        max(c.creationdate) as last_comment_date
    from comments c
    join posts p on p.id = c.postid and p.posttypeid in (1,2)
    group by c.postid
),
-- Map close reason ids to names (null-safe)
close_reasons as (
    select crt.id as close_reason_id, crt.name as close_reason_name
    from closereasontypes crt
),
-- Compute user quality segments
user_segments as (
    select
        ue.user_id,
        case
            when ue.reputation >= 100000 then 'Legend'
            when ue.reputation >= 20000 then 'Expert'
            when ue.reputation >= 5000 then 'Seasoned'
            when ue.reputation >= 1000 then 'Regular'
            else 'Newbie'
        end as segment,
        case
            when ue.answers >= greatest(1, ue.questions) * 2 and ue.received_upvotes > ue.received_downvotes then 'Answerer-Heavy'
            when ue.questions > ue.answers and ue.post_score < 0 then 'Asker-Learning'
            when ue.views > 100000 and ue.post_score >= 0 then 'Popular'
            else 'Balanced'
        end as profile_hint
    from user_engagement ue
),
-- Headline per tag combining usage and recency
tag_headlines as (
    select
        tr.tagname,
        tr.total_tag_count,
        tr.last_tagged_date,
        dense_rank() over (order by tr.total_tag_count desc nulls last) as rank_by_count,
        dense_rank() over (order by tr.last_tagged_date desc nulls last) as rank_by_recency
    from tag_recency tr
),
-- Derive a small working set by combining several dimensions
working as (
    select
        qm.question_id,
        qm.asker_id,
        ue.displayname as asker_name,
        ue.reputation,
        us.segment,
        us.profile_hint,
        qm.title,
        qm.viewcount,
        qm.q_score,
        qm.answercount,
        qm.has_positive_answer,
        qm.favorites,
        coalesce(cr.close_reason_name, 'N/A') as close_reason_name,
        coalesce(qcb.comments_30d, 0) as comments_30d,
        coalesce(qcb.helpful_comments, 0) as helpful_comments,
        qcb.last_comment_date,
        am.median_answer_score
    from question_metrics qm
    left join user_engagement ue on ue.user_id = qm.asker_id
    left join user_segments us on us.user_id = qm.asker_id
    left join close_reasons cr on cr.close_reason_id = qm.close_reason_id
    left join question_comment_buzz qcb on qcb.question_id = qm.question_id
    left join answer_medians am on am.question_id = qm.question_id
),
-- Aggregate tag influence for each question
question_tag_influence as (
    select
        qt.question_id,
        sum(ln(1 + coalesce(th.total_tag_count, 0))) as tag_popularity_score,
        avg(coalesce(th.rank_by_recency, 100000)) as tag_recency_rank_avg
    from question_tags qt
    left join tag_headlines th on th.tagname = qt.tagname
    group by qt.question_id
),
-- Integrate user activity trajectory near the question time
question_activity_trend as (
    select
        q.id as question_id,
        ua.running_post_count,
        ua.running_score,
        ua.trailing_10_avg_score
    from posts q
    left join lateral (
        select ua.*
        from user_activity_window ua
        where ua.user_id = q.owneruserid
          and ua.creationdate <= q.creationdate
        order by ua.creationdate desc
        limit 1
    ) ua on true
    where q.posttypeid = 1
),
-- Score normalization across questions
question_norm as (
    select
        w.question_id,
        w.asker_id,
        w.asker_name,
        w.reputation,
        w.segment,
        w.profile_hint,
        w.title,
        w.viewcount,
        w.q_score,
        w.answercount,
        w.has_positive_answer,
        w.favorites,
        w.close_reason_name,
        w.comments_30d,
        w.helpful_comments,
        w.last_comment_date,
        w.median_answer_score,
        qti.tag_popularity_score,
        qti.tag_recency_rank_avg,
        qat.running_post_count,
        qat.running_score,
        qat.trailing_10_avg_score,
        -- derived composite score with various components
        (
          0.4 * coalesce(w.q_score, 0)
          + 0.2 * ln(1 + coalesce(w.viewcount, 0))
          + 0.1 * coalesce(w.favorites, 0)
          + 0.15 * coalesce(w.median_answer_score, 0)
          + 0.1 * coalesce(qti.tag_popularity_score, 0)
          - 0.05 * coalesce(qti.tag_recency_rank_avg, 0)
        ) as composite_score
    from working w
    left join question_tag_influence qti on qti.question_id = w.question_id
    left join question_activity_trend qat on qat.question_id = w.question_id
),
-- Identify duplicates backlink counts using set operators
duplicate_backlinks as (
    select relatedpostid as target_id, count(*) as incoming_duplicate_count
    from postlinks
    where linktypeid = 3
    group by relatedpostid
    union all
    select postid as target_id, 0 as incoming_duplicate_count
    from posts
    where posttypeid = 1
),
duplicate_agg as (
    select target_id as question_id, sum(incoming_duplicate_count) as incoming_duplicate_count
    from duplicate_backlinks
    group by target_id
),
-- Heavy comments per user to test correlated filtering
heavy_commenters as (
    select
        u.id as user_id,
        count(*) as comment_count_90d
    from users u
    join comments c on c.userid = u.id
    where c.creationdate >= now() - interval '90 days'
    group by u.id
),
final_rank as (
    select
        qn.*,
        da.incoming_duplicate_count,
        hc.comment_count_90d,
        row_number() over (
            order by
                qn.composite_score desc,
                coalesce(da.incoming_duplicate_count, 0) desc,
                qn.viewcount desc,
                qn.q_score desc,
                qn.question_id
        ) as rnk
    from question_norm qn
    left join duplicate_agg da on da.question_id = qn.question_id
    left join heavy_commenters hc on hc.user_id = qn.asker_id
)
select
    fr.rnk,
    fr.question_id,
    fr.title,
    fr.asker_id,
    coalesce(fr.asker_name, '(unknown)') as asker_name,
    fr.segment,
    fr.profile_hint,
    fr.reputation,
    fr.q_score,
    fr.viewcount,
    fr.answercount,
    fr.has_positive_answer,
    fr.favorites,
    fr.median_answer_score,
    fr.tag_popularity_score,
    fr.tag_recency_rank_avg,
    fr.running_post_count,
    fr.running_score,
    fr.trailing_10_avg_score,
    fr.incoming_duplicate_count,
    fr.comment_count_90d,
    fr.close_reason_name,
    fr.comments_30d,
    fr.helpful_comments,
    fr.last_comment_date,
    fr.composite_score
from final_rank fr
where (
    fr.close_reason_name is null
    or fr.close_reason_name not ilike '%duplicate%'
)
and (
    fr.asker_name is null
    or fr.asker_name not ilike any (array['%test%', '%bot%', '%dummy%'])
)
and (
    fr.tag_recency_rank_avg is null
    or fr.tag_recency_rank_avg < 10000
)
order by fr.rnk
limit 200;